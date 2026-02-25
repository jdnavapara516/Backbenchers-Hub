from django.urls import re_path

from .consumers import BingoRoomConsumer, TttRoomConsumer


websocket_urlpatterns = [
    re_path(r"^ws/gamify/(?P<room_id>[A-Za-z0-9_-]+)/$", BingoRoomConsumer.as_asgi()),
    re_path(r"^ws/oxo/(?P<room_id>[A-Za-z0-9_-]+)/$", TttRoomConsumer.as_asgi()),
]
