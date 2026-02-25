from django.urls import path
from .views import create_room, join_room, leaderboard, my_profile, register, room_detail
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

urlpatterns = [
    path('register/', register),
    path('login/', TokenObtainPairView.as_view()),
    path('refresh/', TokenRefreshView.as_view()),
    path('rooms/create/', create_room),
    path('rooms/join/', join_room),
    path('rooms/<str:room_id>/', room_detail),
    path('profile/', my_profile),
    path('leaderboard/', leaderboard),
]
