import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.tokens import AccessToken

User = get_user_model()

class RideConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        # Extract token from query string
        query_string = self.scope['query_string'].decode()
        token_param = next((param.split('=')[1] for param in query_string.split('&') if param.startswith('token=')), None)

        self.user = None
        if token_param:
            try:
                # Authenticate user using JWT token
                access_token = AccessToken(token_param)
                self.user = await self.get_user(access_token['user_id'])
            except Exception as e:
                print(f"WebSocket authentication failed: {e}")
                await self.close()
                return

        if not self.user or not self.user.is_authenticated:
            await self.close()
            return

        self.user_id = str(self.user.id)
        self.user_group_name = f'user_{self.user_id}'
        self.ride_group_name = 'rides' # General group for all ride updates

        # Add user to their personal group and general rides group
        await self.channel_layer.group_add(
            self.user_group_name,
            self.channel_name
        )
        await self.channel_layer.group_add(
            self.ride_group_name,
            self.channel_name
        )

        await self.accept()
        await self.send(text_data=json.dumps({
            'type': 'websocket.connected',
            'message': 'WebSocket connected!',
            'user_id': self.user_id
        }))

    async def disconnect(self, close_code):
        if self.user:
            await self.channel_layer.group_discard(
                self.user_group_name,
                self.channel_name
            )
            await self.channel_layer.group_discard(
                self.ride_group_name,
                self.channel_name
            )

    async def receive(self, text_data):
        text_data_json = json.loads(text_data)
        message_type = text_data_json.get('type')

        if message_type == 'location_update' and self.user.role == 'driver':
            latitude = text_data_json.get('latitude')
            longitude = text_data_json.get('longitude')
            ride_id = text_data_json.get('ride_id') # Assuming ride_id is sent with location

            # For now, just broadcast to the ride group.
            # In a real app, you'd store this in the database and perhaps update driver's active ride.
            await self.channel_layer.group_send(
                f"ride_{ride_id}", # Send to a specific ride group
                {
                    "type": "location.update", # Custom event type
                    "latitude": latitude,
                    "longitude": longitude,
                    "user_id": str(self.user.id),
                    "ride_id": ride_id,
                }
            )
        # Add other message types as needed (e.g., chat messages)

    # Receive message from channel layer group (for general ride updates)
    async def ride_update(self, event):
        message = event['message']
        await self.send(text_data=json.dumps({
            'type': 'ride_update',
            'content': message
        }))

    # Receive message from channel layer group (for location updates)
    async def location_update(self, event):
        await self.send(text_data=json.dumps({
            'type': 'location_update',
            'latitude': event['latitude'],
            'longitude': event['longitude'],
            'user_id': event['user_id'],
            'ride_id': event['ride_id'],
        }))

    # Helper to get user asynchronously
    @database_sync_to_async
    def get_user(self, user_id):
        try:
            return User.objects.get(id=user_id)
        except User.DoesNotExist:
            return None
