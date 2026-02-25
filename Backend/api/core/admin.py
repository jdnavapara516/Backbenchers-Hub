from django.contrib import admin
from .models import Profile, Room, RoomPlayer


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "total_matches", "wins", "second_place", "losses", "points")
    search_fields = ("user__username",)


@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    list_display = ("room_id", "owner", "status", "max_players", "current_turn_player", "created_at")
    list_filter = ("status", "created_at")
    search_fields = ("room_id", "owner__username")


@admin.register(RoomPlayer)
class RoomPlayerAdmin(admin.ModelAdmin):
    list_display = ("room", "user", "turn_order", "status", "lines_completed", "rank", "joined_at")
    list_filter = ("status", "room__status")
    search_fields = ("room__room_id", "user__username")
