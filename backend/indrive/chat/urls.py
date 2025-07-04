from django.urls import path, include
from rest_framework.routers import DefaultRouter
from . import views

router = DefaultRouter()
router.register(r'messages', views.ChatMessageViewSet, basename='chatmessage')

urlpatterns = [
    path('rides/<int:ride_id>/', include(router.urls)),
]