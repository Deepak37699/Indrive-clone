from rest_framework import serializers
from .models import ChatMessage

class ChatMessageSerializer(serializers.ModelSerializer):
    class Meta:
        model = ChatMessage
        fields = ['id', 'ride', 'sender', 'recipient', 'message', 'timestamp', 'is_read']
        read_only_fields = ['sender', 'timestamp']

class ChatMessageUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = ChatMessage
        fields = ['is_read']