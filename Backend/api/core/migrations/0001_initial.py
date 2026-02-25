from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="Profile",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("total_matches", models.PositiveIntegerField(default=0)),
                ("wins", models.PositiveIntegerField(default=0)),
                ("second_place", models.PositiveIntegerField(default=0)),
                ("losses", models.PositiveIntegerField(default=0)),
                ("points", models.PositiveIntegerField(default=0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="profile",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
        ),
        migrations.CreateModel(
            name="Room",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("room_id", models.CharField(db_index=True, max_length=12, unique=True)),
                ("max_players", models.PositiveSmallIntegerField(default=5)),
                (
                    "status",
                    models.CharField(
                        choices=[("WAITING", "Waiting"), ("STARTED", "Started"), ("ENDED", "Ended")],
                        db_index=True,
                        default="WAITING",
                        max_length=10,
                    ),
                ),
                ("called_numbers", models.JSONField(blank=True, default=list)),
                ("turn_deadline", models.DateTimeField(blank=True, null=True)),
                ("winner_order", models.JSONField(blank=True, default=list)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "current_turn_player",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="turn_rooms",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "owner",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="owned_rooms",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.CreateModel(
            name="RoomPlayer",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("turn_order", models.PositiveSmallIntegerField()),
                (
                    "status",
                    models.CharField(
                        choices=[("PLAYING", "Playing"), ("SKIPPED", "Skipped"), ("FINISHED", "Finished")],
                        default="PLAYING",
                        max_length=10,
                    ),
                ),
                ("board_numbers", models.JSONField(blank=True, default=list)),
                ("eliminated_numbers", models.JSONField(blank=True, default=list)),
                ("lines_completed", models.PositiveSmallIntegerField(default=0)),
                ("rank", models.PositiveSmallIntegerField(blank=True, null=True)),
                ("joined_at", models.DateTimeField(auto_now_add=True)),
                (
                    "room",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="players", to="core.room"),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="room_entries",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["turn_order", "joined_at"],
                "unique_together": {("room", "user")},
            },
        ),
    ]
