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

        # Real-time location tracking handler
        if message_type == 'location_ping':
            ride_id = text_data_json.get('ride_id')
            lat = text_data_json.get('latitude')
            lng = text_data_json.get('longitude')
            
            # Broadcast to ride group
            await self.channel_layer.group_send(
                f"ride_{ride_id}", {
                    "type": "location.update",
                    "latitude": lat,
                    "longitude": lng,
                    "timestamp": datetime.now().isoformat(),
                    "driver_id": str(self.user.id)
                }
            )
            
            # Update ride ETA
            await self.update_ride_eta(ride_id, lat, lng)
            return

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

    @database_sync_to_async
    def update_ride_eta(self, ride_id, current_lat, current_lng):
        """Update ride ETA and broadcast to connected clients"""
        try:
            ride = Ride.objects.get(id=ride_id)
            destination_lat = ride.destination_latitude
            destination_lng = ride.destination_longitude
            
            # Calculate new ETA
            eta_data = calculate_eta(current_lat, current_lng,
                                   destination_lat, destination_lng)
            if eta_data:
                ride.eta_minutes = eta_data['eta']
                ride.distance_km = eta_data['distance']
                ride.save()
                
                # Broadcast updated ETA
                async_to_sync(self.channel_layer.group_send)(
                    f"ride_{ride_id}", {
                        "type": "eta.update",
                        "eta": eta_data['eta'],
                        "distance": eta_data['distance'],
                        "polyline": eta_data['polyline']
                    }
                )
        except Ride.DoesNotExist:
            print(f"Ride {ride_id} not found for ETA update")
        except Exception as e:
            print(f"Error updating ETA: {e}")
