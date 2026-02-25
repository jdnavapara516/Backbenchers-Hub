import random
import string

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from django.db import models
from .models import GameStatus, Profile, Room, RoomPlayer
from .serializers import CreateRoomSerializer, JoinRoomSerializer, ProfileSerializer, RegisterSerializer, RoomSerializer


@api_view(['POST'])

def register(request):
    serializer = RegisterSerializer(data=request.data)
    if serializer.is_valid():
        user = serializer.save()
        return Response(RegisterSerializer(user).data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors)


def _generate_room_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))


def _build_board():
    numbers = list(range(1, 26))
    random.shuffle(numbers)
    return numbers


def _broadcast_room_snapshot(room):
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    prefix = "ttt_room" if room.game_type == "OXO" else "bingo_room"
    
    payload = {
        "type": "room_snapshot",
        "data": RoomSerializer(room).data,
    }
    async_to_sync(channel_layer.group_send)(
        f"{prefix}_{room.room_id}",
        {"type": "room.event", "payload": payload},
    )


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def create_room(request):
    serializer = CreateRoomSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    room_id = _generate_room_id()
    while Room.objects.filter(room_id=room_id).exists():
        room_id = _generate_room_id()

    game_type = serializer.validated_data.get("game_type", "BINGO")
    max_players = serializer.validated_data["max_players"]
    
    if game_type == "OXO":
        max_players = 2

    room = Room.objects.create(
        room_id=room_id,
        owner=request.user,
        max_players=max_players,
        game_type=game_type,
    )
    RoomPlayer.objects.create(
        room=room,
        user=request.user,
        turn_order=1,
        board_numbers=_build_board() if game_type == "BINGO" else [],
    )
    _broadcast_room_snapshot(room)
    return Response(RoomSerializer(room).data, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def join_room(request):
    serializer = JoinRoomSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    room = get_object_or_404(Room, room_id=serializer.validated_data["room_id"].upper())
    if room.status != GameStatus.WAITING:
        return Response({"detail": "Room already started or ended"}, status=status.HTTP_400_BAD_REQUEST)

    if RoomPlayer.objects.filter(room=room, user=request.user).exists():
        return Response(RoomSerializer(room).data, status=status.HTTP_200_OK)

    current_players = room.players.count()
    if current_players >= room.max_players:
        return Response({"detail": "Room is full"}, status=status.HTTP_400_BAD_REQUEST)

    RoomPlayer.objects.create(
        room=room,
        user=request.user,
        turn_order=current_players + 1,
        board_numbers=_build_board() if room.game_type == "BINGO" else [],
    )
    room.refresh_from_db()
    _broadcast_room_snapshot(room)
    return Response(RoomSerializer(room).data, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def room_detail(request, room_id):
    room = get_object_or_404(Room, room_id=room_id.upper())
    return Response(RoomSerializer(room).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def leaderboard(request):
    # Sort by calculated win rate (wins/total * 100) or 0.0, then by points
    profiles = Profile.objects.select_related("user").annotate(
        calculated_win_rate=models.Case(
            models.When(total_matches=0, then=models.Value(0.0)),
            default=models.ExpressionWrapper(
                models.F('wins') * 100.0 / models.F('total_matches'),
                output_field=models.FloatField()
            ),
            output_field=models.FloatField(),
        )
    ).order_by("-calculated_win_rate", "-points")
    
    return Response(ProfileSerializer(profiles, many=True).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def my_profile(request):
    return Response(ProfileSerializer(request.user.profile).data)
