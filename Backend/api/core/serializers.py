from django.contrib.auth.models import User
from rest_framework import serializers
from .models import Profile, Room, RoomPlayer


class ProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)
    win_rate = serializers.FloatField(read_only=True)

    class Meta:
        model = Profile
        fields = [
            "username",
            "total_matches",
            "wins",
            "second_place",
            "losses",
            "points",
            "win_rate",
        ]


class RegisterSerializer(serializers.ModelSerializer):
    profile = ProfileSerializer(read_only=True)

    class Meta:
        model = User
        fields = ["id", "username", "password", "profile"]
        extra_kwargs = {"password": {"write_only": True}}

    def create(self, validated_data):
        user = User.objects.create_user(**validated_data)
        return user


class RoomPlayerSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)

    class Meta:
        model = RoomPlayer
        fields = [
            "user",
            "username",
            "turn_order",
            "status",
            "lines_completed",
            "rank",
            "joined_at",
        ]


class RoomSerializer(serializers.ModelSerializer):
    owner_username = serializers.CharField(source="owner.username", read_only=True)
    current_turn_username = serializers.CharField(source="current_turn_player.username", read_only=True)
    players = RoomPlayerSerializer(many=True, read_only=True)
    current_players = serializers.SerializerMethodField()

    class Meta:
        model = Room
        fields = [
            "room_id",
            "owner",
            "owner_username",
            "max_players",
            "current_players",
            "game_type",
            "status",
            "current_turn_player",
            "current_turn_username",
            "called_numbers",
            "turn_deadline",
            "winner_order",
            "players",
            "created_at",
        ]

    def get_current_players(self, obj):
        return obj.players.count()


class CreateRoomSerializer(serializers.Serializer):
    max_players = serializers.IntegerField(required=False, min_value=2, max_value=5, default=5)
    game_type = serializers.ChoiceField(choices=["BINGO", "OXO"], default="BINGO")


class JoinRoomSerializer(serializers.Serializer):
    room_id = serializers.CharField(max_length=12)
