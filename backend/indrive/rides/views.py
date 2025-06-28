from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from .models import Ride
from .serializers import RideSerializer
from users.models import User # Import User model
from django.db.models import Q # For complex queries
from django.utils import timezone # Import timezone for accepted_at, completed_at
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
import json

class RideRequestView(generics.CreateAPIView):
    queryset = Ride.objects.all()
    serializer_class = RideSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        # Ensure only riders can request rides
        if self.request.user.role != 'rider':
            raise serializers.ValidationError("Only riders can request rides.")
        
        ride = serializer.save(rider=self.request.user, status='requested')

        # Send WebSocket notification to all drivers about new ride request
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            "rides",  # Group name for all drivers
            {
                "type": "ride_update",
                "message": json.dumps(RideSerializer(ride).data) # Send ride data
            }
        )
        # Also add rider to their specific ride group for updates
        async_to_sync(channel_layer.group_add)(
            f"ride_{ride.id}",
            f"user_{ride.rider.id}"
        )
        
class RiderRideListView(generics.ListAPIView):
    serializer_class = RideSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # Return rides requested by the current rider
        return Ride.objects.filter(rider=self.request.user).order_by('-created_at')

class DriverRideListView(generics.ListAPIView):
    serializer_class = RideSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # Return rides that are 'requested' and 'accepted' by the current driver
        # Only show requested rides to available drivers
        if self.request.user.role == 'driver' and self.request.user.is_available:
            return Ride.objects.filter(Q(status='requested') | Q(driver=self.request.user, status='accepted')).order_by('-created_at')
        elif self.request.user.role == 'driver' and not self.request.user.is_available:
            # If driver is not available, only show their accepted/started rides
            return Ride.objects.filter(driver=self.request.user, status__in=['accepted', 'started', 'completed', 'cancelled']).order_by('-created_at')
        return Ride.objects.none() # Should not happen for non-drivers

class RideDetailView(generics.RetrieveUpdateAPIView):
    queryset = Ride.objects.all()
    serializer_class = RideSerializer
    permission_classes = [IsAuthenticated]
    lookup_field = 'pk'

    def patch(self, request, *args, **kwargs):
        ride = self.get_object()
        user = request.user

        # Driver accepts a ride
        if 'status' in request.data and request.data['status'] == 'accepted':
            if user.role == 'driver' and ride.status == 'requested' and ride.driver is None:
                ride.driver = user
                ride.status = 'accepted'
                ride.accepted_at = timezone.now()
                ride.save()
                
                # Notify the rider that their ride has been accepted
                channel_layer = get_channel_layer()
                async_to_sync(channel_layer.group_send)(
                    f"user_{ride.rider.id}",
                    {
                        "type": "ride_update",
                        "message": json.dumps(RideSerializer(ride).data)
                    }
                )
                # Add driver to the ride's specific group
                async_to_sync(channel_layer.group_add)(
                    f"ride_{ride.id}",
                    f"user_{ride.driver.id}"
                )
                return Response(RideSerializer(ride).data)
            else:
                return Response({"detail": "Cannot accept this ride."}, status=status.HTTP_400_BAD_REQUEST)
        
        # Add more status transitions as needed (e.g., started, completed, cancelled)
        if 'status' in request.data and request.data['status'] == 'started':
            if user.role == 'driver' and ride.driver == user and ride.status == 'accepted':
                ride.status = 'started'
                ride.save()
                # Notify both rider and driver of status change
                channel_layer = get_channel_layer()
                async_to_sync(channel_layer.group_send)(
                    f"ride_{ride.id}", # Send to ride-specific group
                    {
                        "type": "ride_update",
                        "message": json.dumps(RideSerializer(ride).data)
                    }
                )
                return Response(RideSerializer(ride).data)
            else:
                return Response({"detail": "Cannot start this ride."}, status=status.HTTP_400_BAD_REQUEST)

        if 'status' in request.data and request.data['status'] == 'completed':
            if user.role == 'driver' and ride.driver == user and ride.status == 'started':
                ride.status = 'completed'
                ride.completed_at = timezone.now()
                # For MVP, just complete. Later, calculate fare.
                ride.save()
                # Notify both rider and driver of status change
                channel_layer = get_channel_layer()
                async_to_sync(channel_layer.group_send)(
                    f"ride_{ride.id}", # Send to ride-specific group
                    {
                        "type": "ride_update",
                        "message": json.dumps(RideSerializer(ride).data)
                    }
                )
                return Response(RideSerializer(ride).data)
            else:
                return Response({"detail": "Cannot complete this ride."}, status=status.HTTP_400_BAD_REQUEST)

        # Allow riders to cancel their own requested rides
        if 'status' in request.data and request.data['status'] == 'cancelled':
            if user.role == 'rider' and ride.rider == user and ride.status == 'requested':
                ride.status = 'cancelled'
                ride.save()
                # Notify both rider and driver of cancellation
                channel_layer = get_channel_layer()
                async_to_sync(channel_layer.group_send)(
                    f"ride_{ride.id}", # Send to ride-specific group
                    {
                        "type": "ride_update",
                        "message": json.dumps(RideSerializer(ride).data)
                    }
                )
                return Response(RideSerializer(ride).data)
            else:
                return Response({"detail": "Cannot cancel this ride."}, status=status.HTTP_400_BAD_REQUEST)

        return super().patch(request, *args, **kwargs) # For other partial updates
