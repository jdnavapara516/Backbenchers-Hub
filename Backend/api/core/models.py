from django.conf import settings
from django.db import models
from django.db.models.signals import post_save
from django.dispatch import receiver


class GameStatus(models.TextChoices):
    WAITING = "WAITING", "Waiting"
    STARTED = "STARTED", "Started"
    ENDED = "ENDED", "Ended"


class GameType(models.TextChoices):
    BINGO = "BINGO", "Bingo"
    OXO = "OXO", "Tic-Tac-Toe"


class PlayerStatus(models.TextChoices):
    PLAYING = "PLAYING", "Playing"
    SKIPPED = "SKIPPED", "Skipped"
    FINISHED = "FINISHED", "Finished"


class Profile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="profile")
    total_matches = models.PositiveIntegerField(default=0)
    wins = models.PositiveIntegerField(default=0)
    second_place = models.PositiveIntegerField(default=0)
    losses = models.PositiveIntegerField(default=0)
    points = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def win_rate(self):
        if self.total_matches == 0:
            return 0.0
        return round((self.wins / self.total_matches) * 100, 2)

    def __str__(self):
        return f"{self.user.username} profile"


class Room(models.Model):
    room_id = models.CharField(max_length=12, unique=True, db_index=True)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="owned_rooms")
    max_players = models.PositiveSmallIntegerField(default=5)
    game_type = models.CharField(max_length=10, choices=GameType.choices, default=GameType.BINGO)
    status = models.CharField(max_length=10, choices=GameStatus.choices, default=GameStatus.WAITING, db_index=True)
    current_turn_player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="turn_rooms",
    )
    called_numbers = models.JSONField(default=list, blank=True)
    turn_deadline = models.DateTimeField(null=True, blank=True)
    winner_order = models.JSONField(default=list, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.room_id} ({self.status})"


class RoomPlayer(models.Model):
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="players")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="room_entries")
    turn_order = models.PositiveSmallIntegerField()
    status = models.CharField(max_length=10, choices=PlayerStatus.choices, default=PlayerStatus.PLAYING)
    board_numbers = models.JSONField(default=list, blank=True)
    eliminated_numbers = models.JSONField(default=list, blank=True)
    lines_completed = models.PositiveSmallIntegerField(default=0)
    rank = models.PositiveSmallIntegerField(null=True, blank=True)
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("room", "user")
        ordering = ["turn_order", "joined_at"]

    def __str__(self):
        return f"{self.room.room_id} - {self.user.username}"


@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def create_user_profile(sender, instance, created, **kwargs):
    if created:
        Profile.objects.create(user=instance)

