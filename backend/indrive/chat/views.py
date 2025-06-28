from rest_framework import viewsets, permissions
from .models import ChatMessage
from .serializers import ChatMessageSerializer, ChatMessageUpdateSerializer

class ChatMessageViewSet(viewsets.ModelViewSet):
    serializer_class = ChatMessageSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        ride_id = self.kwargs['ride_id']
        return ChatMessage.objects.filter(
            ride_id=ride_id,
            recipient=self.request.user
        ).order_by('-timestamp')

    def perform_create(self, serializer):
        ride_id = self.kwargs['ride_id']
        serializer.save(
            sender=self.request.user,
            ride_id=ride_id
        )

    def get_serializer_class(self):
        if self.action in ['update', 'partial_update']:
            return ChatMessageUpdateSerializer
        return super().get_serializer_class()