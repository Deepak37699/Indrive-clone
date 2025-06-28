import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from .models import ChatMessage
from rides.models import Ride

class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.ride_id = self.scope['url_route']['kwargs']['ride_id']
        self.user = self.scope['user']
        
        if not self.user.is_authenticated:
            await self.close()
            return

        self.room_group_name = f'chat_{self.ride_id}'
        
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name
        )

    async def receive(self, text_data):
        data = json.loads(text_data)
        message = data['message']
        recipient_id = data['recipient_id']
        
        # Save message to database
        message_obj = await self.create_message(message, recipient_id)
        
        # Broadcast to room group
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'chat_message',
                'message': message,
                'sender_id': self.user.id,
                'timestamp': message_obj.timestamp.isoformat()
            }
        )

    async def chat_message(self, event):
        await self.send(text_data=json.dumps(event))

    @database_sync_to_async
    def create_message(self, message, recipient_id):
        from users.models import User
        recipient = User.objects.get(id=recipient_id)
        ride = Ride.objects.get(id=self.ride_id)
        
        return ChatMessage.objects.create(
            ride=ride,
            sender=self.user,
            recipient=recipient,
            message=message
        )