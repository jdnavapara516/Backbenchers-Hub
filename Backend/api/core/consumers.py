import asyncio
import random
from datetime import timedelta

from asgiref.sync import sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.db import transaction
from django.utils import timezone

from .bingo import calculate_completed_lines
from .models import GameStatus, PlayerStatus, Profile, Room, RoomPlayer


class BingoRoomConsumer(AsyncJsonWebsocketConsumer):
    _timer_tasks = {}

    @staticmethod
    def group_name(room_id):
        return f"bingo_room_{room_id}"

    async def connect(self):
        self.room_id = self.scope["url_route"]["kwargs"]["room_id"].upper()
        self.group = self.group_name(self.room_id)
        user = self.scope["user"]

        if not user or user.is_anonymous:
            await self.close(code=4001)
            return

        if not await self._is_room_player(self.room_id, user.id):
            await self.close(code=4003)
            return

        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()

        snapshot = await self._room_snapshot(self.room_id)
        await self.send_json({"type": "room_snapshot", "data": snapshot})
        await self._schedule_timeout_if_needed(snapshot)

    async def disconnect(self, close_code):
        if hasattr(self, "group"):
            await self.channel_layer.group_discard(self.group, self.channel_name)

    async def receive_json(self, content, **kwargs):
        action = content.get("action")
        user = self.scope["user"]
        try:
            if action == "start_game":
                payload = await self._start_game(self.room_id, user.id)
                await self.channel_layer.group_send(self.group, {"type": "room.event", "payload": payload})
                await self._schedule_timeout_if_needed(payload["data"])
                return

            if action == "mark_number":
                number = content.get("number")
                payload = await self._make_move(self.room_id, user.id, number)
                await self.channel_layer.group_send(self.group, {"type": "room.event", "payload": payload})
                if payload["type"] != "game_ended":
                    await self._schedule_timeout_if_needed(payload["data"])
                return

            if action == "room_state":
                snapshot = await self._room_snapshot(self.room_id)
                await self.send_json({"type": "room_snapshot", "data": snapshot})
                return

            await self.send_json({"type": "error", "message": "Unknown action"})
        except ValueError as exc:
            await self.send_json({"type": "error", "message": str(exc)})

    async def room_event(self, event):
        await self.send_json(event["payload"])

    async def _schedule_timeout_if_needed(self, room_data):
        if room_data["status"] != GameStatus.STARTED or not room_data.get("turn_deadline"):
            return

        room_id = room_data["room_id"]
        existing = self._timer_tasks.get(room_id)
        if existing and not existing.done():
            existing.cancel()

        self._timer_tasks[room_id] = asyncio.create_task(self._timeout_task(room_id, room_data["turn_deadline"]))

    async def _timeout_task(self, room_id, deadline_iso):
        try:
            deadline = timezone.datetime.fromisoformat(deadline_iso)
            now = timezone.now()
            wait_seconds = max((deadline - now).total_seconds(), 0)
            await asyncio.sleep(wait_seconds + 0.1)

            payload = await self._auto_skip_turn(room_id, deadline_iso)
            if payload:
                await self.channel_layer.group_send(
                    self.group_name(room_id),
                    {"type": "room.event", "payload": payload},
                )
                if payload["type"] != "game_ended":
                    await self._schedule_timeout_if_needed(payload["data"])
        except asyncio.CancelledError:
            return

    @sync_to_async
    def _is_room_player(self, room_id, user_id):
        return RoomPlayer.objects.filter(room__room_id=room_id, user_id=user_id).exists()

    def _room_snapshot_sync(self, room_id):
        room = Room.objects.select_related("owner", "current_turn_player").prefetch_related("players__user").get(room_id=room_id)
        players = []
        for entry in room.players.all().order_by("turn_order"):
            players.append(
                {
                    "user_id": entry.user_id,
                    "username": entry.user.username,
                    "turn_order": entry.turn_order,
                    "status": entry.status,
                    "board_numbers": entry.board_numbers,
                    "lines_completed": entry.lines_completed,
                    "rank": entry.rank,
                }
            )

        return {
            "room_id": room.room_id,
            "owner_id": room.owner_id,
            "owner_username": room.owner.username,
            "status": room.status,
            "max_players": room.max_players,
            "current_turn_player_id": room.current_turn_player_id,
            "current_turn_username": room.current_turn_player.username if room.current_turn_player else None,
            "called_numbers": room.called_numbers,
            "turn_deadline": room.turn_deadline.isoformat() if room.turn_deadline else None,
            "winner_order": room.winner_order,
            "players": players,
        }

    @sync_to_async
    def _room_snapshot(self, room_id):
        return self._room_snapshot_sync(room_id)

    def _next_turn_player(self, room, players):
        if not players:
            return None

        available = [p for p in players if p.status != PlayerStatus.FINISHED]
        if not available:
            return None

        current_id = room.current_turn_player_id
        if current_id is None:
            return available[0]

        ordered = players
        current_idx = next((idx for idx, item in enumerate(ordered) if item.user_id == current_id), -1)
        for offset in range(1, len(ordered) + 1):
            candidate = ordered[(current_idx + offset) % len(ordered)]
            if candidate.status != PlayerStatus.FINISHED:
                return candidate
        return None

    def _build_board(self):
        numbers = list(range(1, 26))
        random.shuffle(numbers)
        return numbers

    def _assign_unique_boards(self, players):
        used = set()
        for player in players:
            candidate = tuple(self._build_board())
            while candidate in used:
                candidate = tuple(self._build_board())
            used.add(candidate)
            player.board_numbers = list(candidate)

    def _finalize_game(self, room, players):
        room.status = GameStatus.ENDED
        room.current_turn_player = None
        room.turn_deadline = None
        room.save(update_fields=["status", "current_turn_player", "turn_deadline", "updated_at"])

        for player in players:
            profile, _ = Profile.objects.get_or_create(user=player.user)
            profile.total_matches += 1
            if player.rank == 1:
                profile.wins += 1
                profile.points += 10
            elif player.rank == 2:
                profile.second_place += 1
                profile.points += 5
            else:
                profile.losses += 1
            profile.save()

    @sync_to_async
    def _start_game(self, room_id, user_id):
        with transaction.atomic():
            room = Room.objects.select_for_update().select_related("owner").get(room_id=room_id)
            if room.owner_id != user_id:
                raise ValueError("Only room owner can start the game")
            if room.status != GameStatus.WAITING:
                raise ValueError("Game already started or ended")

            players = list(room.players.select_for_update().order_by("turn_order"))
            if len(players) < 2:
                raise ValueError("Need at least 2 players to start")

            room.status = GameStatus.STARTED
            room.called_numbers = []
            room.winner_order = []
            room.current_turn_player = players[0].user
            room.turn_deadline = timezone.now() + timedelta(seconds=10)
            room.save()

            self._assign_unique_boards(players)
            for player in players:
                player.status = PlayerStatus.PLAYING
                player.rank = None
                player.lines_completed = 0
                player.eliminated_numbers = []
                player.save()

        return {"type": "game_started", "data": self._room_snapshot_sync(room_id)}

    @sync_to_async
    def _make_move(self, room_id, user_id, number):
        if not isinstance(number, int) or not (1 <= number <= 25):
            raise ValueError("Number must be in range 1..25")

        with transaction.atomic():
            room = Room.objects.select_for_update().get(room_id=room_id)
            if room.status != GameStatus.STARTED:
                raise ValueError("Game is not in started state")
            if room.current_turn_player_id != user_id:
                raise ValueError("Not your turn")
            if room.turn_deadline and timezone.now() > room.turn_deadline:
                raise ValueError("Turn expired")
            if number in room.called_numbers:
                raise ValueError("Number already eliminated")

            room.called_numbers = [*room.called_numbers, number]
            players = list(
                RoomPlayer.objects.select_for_update()
                .select_related("user")
                .filter(room=room)
                .order_by("turn_order")
            )

            for player in players:
                if number not in player.eliminated_numbers:
                    player.eliminated_numbers = [*player.eliminated_numbers, number]
                player.lines_completed = calculate_completed_lines(player.board_numbers, player.eliminated_numbers)
                if player.user_id == user_id and player.status == PlayerStatus.SKIPPED:
                    player.status = PlayerStatus.PLAYING
                if player.lines_completed >= 5 and player.rank is None:
                    next_rank = 1 + sum(1 for p in players if p.rank is not None)
                    player.rank = next_rank
                    player.status = PlayerStatus.FINISHED
                    if player.user_id not in room.winner_order:
                        room.winner_order = [*room.winner_order, player.user_id]
                player.save()

            ranked_count = sum(1 for p in players if p.rank is not None)
            winner_threshold = 2 if len(players) > 2 else 1
            should_end = ranked_count >= winner_threshold or len(room.called_numbers) >= 25
            if should_end:
                self._finalize_game(room, players)
                event_type = "game_ended"
            else:
                next_player = self._next_turn_player(room, players)
                room.current_turn_player = next_player.user if next_player else None
                room.turn_deadline = timezone.now() + timedelta(seconds=10) if next_player else None
                room.save(update_fields=["called_numbers", "winner_order", "current_turn_player", "turn_deadline", "updated_at"])
                event_type = "turn_changed"

        return {"type": event_type, "data": self._room_snapshot_sync(room_id)}

    @sync_to_async
    def _auto_skip_turn(self, room_id, expected_deadline):
        with transaction.atomic():
            room = Room.objects.select_for_update().get(room_id=room_id)
            if room.status != GameStatus.STARTED or not room.turn_deadline:
                return None
            if room.turn_deadline.isoformat() != expected_deadline:
                return None
            if timezone.now() < room.turn_deadline:
                return None

            players = list(
                RoomPlayer.objects.select_for_update()
                .select_related("user")
                .filter(room=room)
                .order_by("turn_order")
            )

            skipped = next((p for p in players if p.user_id == room.current_turn_player_id), None)
            if skipped and skipped.status != PlayerStatus.FINISHED:
                skipped.status = PlayerStatus.SKIPPED
                skipped.save(update_fields=["status"])

            next_player = self._next_turn_player(room, players)
            if not next_player:
                self._finalize_game(room, players)
                return {"type": "game_ended", "data": self._room_snapshot_sync(room_id)}

            room.current_turn_player = next_player.user
            room.turn_deadline = timezone.now() + timedelta(seconds=10)
            room.save(update_fields=["current_turn_player", "turn_deadline", "updated_at"])

        return {
            "type": "turn_auto_skipped",
            "data": self._room_snapshot_sync(room_id),
        }

class TttRoomConsumer(BingoRoomConsumer):
    @staticmethod
    def group_name(room_id):
        return f"ttt_room_{room_id}"

    def _check_win(self, board):
        # board is a list of 9 elements: None, user_id1, user_id2
        wins = [
            (0, 1, 2), (3, 4, 5), (6, 7, 8), # rows
            (0, 3, 6), (1, 4, 7), (2, 5, 8), # cols
            (0, 4, 8), (2, 4, 6)             # diags
        ]
        for a, b, c in wins:
            if board[a] and board[a] == board[b] == board[c]:
                return board[a]
        return None

    @sync_to_async
    def _start_game(self, room_id, user_id):
        with transaction.atomic():
            room = Room.objects.select_for_update().select_related("owner").get(room_id=room_id)
            if room.owner_id != user_id:
                raise ValueError("Only room owner can start the game")
            if room.status != GameStatus.WAITING:
                raise ValueError("Game already started or ended")

            players = list(room.players.select_for_update().order_by("turn_order"))
            if len(players) != 2:
                raise ValueError("Need exactly 2 players for Tic-Tac-Toe")

            room.status = GameStatus.STARTED
            room.called_numbers = [None] * 9  # Use this to store the board: [user_id, None, ...]
            room.winner_order = []
            room.current_turn_player = players[0].user
            room.turn_deadline = timezone.now() + timedelta(seconds=30)
            room.save()

            for player in players:
                player.status = PlayerStatus.PLAYING
                player.rank = None
                player.save()

        return {"type": "game_started", "data": self._room_snapshot_sync(room_id)}

    @sync_to_async
    def _make_move(self, room_id, user_id, cell_index):
        if not isinstance(cell_index, int) or not (0 <= cell_index <= 8):
            raise ValueError("Invalid cell index")

        with transaction.atomic():
            room = Room.objects.select_for_update().get(room_id=room_id)
            if room.status != GameStatus.STARTED:
                raise ValueError("Game is not in started state")
            if room.current_turn_player_id != user_id:
                raise ValueError("Not your turn")
            if room.turn_deadline and timezone.now() > room.turn_deadline:
                raise ValueError("Turn expired")
            
            board = room.called_numbers
            if board[cell_index] is not None:
                raise ValueError("Cell already occupied")

            board[cell_index] = user_id
            room.called_numbers = board
            
            winner_id = self._check_win(board)
            players = list(room.players.select_related("user").order_by("turn_order"))
            
            if winner_id:
                room.status = GameStatus.ENDED
                room.winner_order = [winner_id]
                room.current_turn_player = None
                room.turn_deadline = None
                room.save()
                
                # Update profiles
                for p in players:
                    profile, _ = Profile.objects.get_or_create(user=p.user)
                    profile.total_matches += 1
                    if p.user_id == winner_id:
                        p.rank = 1
                        profile.wins += 1
                        profile.points += 10
                    else:
                        p.rank = 2
                        profile.losses += 1
                    p.save()
                    profile.save()
                
                return {"type": "game_ended", "data": self._room_snapshot_sync(room_id)}
            
            # Check draw
            if all(cell is not None for cell in board):
                room.status = GameStatus.ENDED
                room.current_turn_player = None
                room.turn_deadline = None
                room.save()
                for p in players:
                    profile, _ = Profile.objects.get_or_create(user=p.user)
                    profile.total_matches += 1
                    profile.save()
                return {"type": "game_ended", "data": self._room_snapshot_sync(room_id)}

            # Next turn
            next_player = next(p for p in players if p.user_id != user_id)
            room.current_turn_player = next_player.user
            room.turn_deadline = timezone.now() + timedelta(seconds=30)
            room.save()

        return {"type": "turn_changed", "data": self._room_snapshot_sync(room_id)}


    async def receive_json(self, content, **kwargs):
        action = content.get("action")
        user = self.scope["user"]
        try:
            if action == "start_game":
                payload = await self._start_game(self.room_id, user.id)
                await self.channel_layer.group_send(self.group, {"type": "room.event", "payload": payload})
                await self._schedule_timeout_if_needed(payload["data"])
                return

            if action == "mark_number":
                number = content.get("number")
                payload = await self._make_move(self.room_id, user.id, number)
                await self.channel_layer.group_send(self.group, {"type": "room.event", "payload": payload})
                if payload["type"] != "game_ended":
                    await self._schedule_timeout_if_needed(payload["data"])
                return

            if action == "rematch":
                payload = await self._rematch(self.room_id, user.id)
                await self.channel_layer.group_send(self.group, {"type": "room.event", "payload": payload})
                await self._schedule_timeout_if_needed(payload["data"])
                return

            if action == "room_state":
                snapshot = await self._room_snapshot(self.room_id)
                await self.send_json({"type": "room_snapshot", "data": snapshot})
                return

            await self.send_json({"type": "error", "message": "Unknown action"})
        except ValueError as exc:
            await self.send_json({"type": "error", "message": str(exc)})

    @sync_to_async
    def _rematch(self, room_id, user_id):
        with transaction.atomic():
            room = Room.objects.select_for_update().get(room_id=room_id)
            if room.status != GameStatus.ENDED:
                raise ValueError("Game is still in progress")
            
            # Reset room
            room.status = GameStatus.STARTED
            room.called_numbers = [None] * 9
            room.winner_order = []
            players = list(room.players.all().order_by("turn_order"))
            room.current_turn_player = players[0].user
            room.turn_deadline = timezone.now() + timedelta(seconds=30)
            room.save()

            for player in players:
                player.status = PlayerStatus.PLAYING
                player.rank = None
                player.save()
        
        return {"type": "game_started", "data": self._room_snapshot_sync(room_id)}

    @sync_to_async
    def _auto_skip_turn(self, room_id, expected_deadline):
        with transaction.atomic():
            room = Room.objects.select_for_update().get(room_id=room_id)
            if room.status != GameStatus.STARTED or not room.turn_deadline:
                return None
            if room.turn_deadline.isoformat() != expected_deadline:
                return None
            
            players = list(room.players.select_related("user").order_by("turn_order"))
            next_player = next(p for p in players if p.user_id != room.current_turn_player_id)
            
            room.current_turn_player = next_player.user
            room.turn_deadline = timezone.now() + timedelta(seconds=30)
            room.save()

        return {"type": "turn_auto_skipped", "data": self._room_snapshot_sync(room_id)}
