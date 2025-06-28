from rest_framework import generics, status, viewsets
from rest_framework.decorators import action
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

class RideViewSet(viewsets.ModelViewSet):
    queryset = Ride.objects.all()
    queryset = Ride.objects.all()
    serializer_class = RideSerializer
    permission_classes = [IsAuthenticated]

    def create(self, request, *args, **kwargs):
        """Handle ride creation with WebSocket notifications"""
        if request.user.role != 'rider':
            return Response({"error": "Only riders can request rides"},
                          status=status.HTTP_403_FORBIDDEN)
        
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        ride = serializer.save(rider=request.user, status='requested')

        # Send WebSocket notification
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            "rides", {
                "type": "ride_update",
                "message": json.dumps(RideSerializer(ride).data)
            }
        )
        async_to_sync(channel_layer.group_add)(
            f"ride_{ride.id}", f"user_{ride.rider.id}"
        )

        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)

    @action(detail=True, methods=['post'], url_path='submit-initial')
    def submit_initial_proposal(self, request, pk=None):
        ride = self.get_object()
        if ride.rider != request.user:
            return Response({"error": "Only ride creator can submit proposals"},
                          status=status.HTTP_403_FORBIDDEN)
        
        serializer = BidSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        ride.proposed_fare = serializer.validated_data['amount']
        ride.proposal_type = 'passenger'
        ride.save()
        
        return Response(RideSerializer(ride).data)

    @action(detail=True, methods=['post'], url_path='submit-counter')
    def submit_counter_offer(self, request, pk=None):
        ride = self.get_object()
        if ride.rider != request.user:
            return Response({"error": "Only ride creator can counter offer"},
                          status=status.HTTP_403_FORBIDDEN)
        
        serializer = BidSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        ride.passenger_counter_offers.append({
            'amount': serializer.validated_data['amount'],
            'timestamp': timezone.now().isoformat(),
            'message': serializer.validated_data.get('message', '')
        })
        ride.save()
        
        return Response(RideSerializer(ride).data)

    @action(detail=True, methods=['post'], url_path='driver-bid')
    def submit_driver_bid(self, request, pk=None):
        ride = self.get_object()
        if not request.user.is_driver:
            return Response({"error": "Only drivers can bid"},
                          status=status.HTTP_403_FORBIDDEN)
        
        serializer = BidSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        ride.driver_proposals.append({
            'driver': request.user.id,
            'amount': serializer.validated_data['amount'],
            'timestamp': timezone.now().isoformat(),
            'message': serializer.validated_data.get('message', '')
        })
        ride.save()

        # Notify rider about new bid
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f"user_{ride.rider.id}", {
                "type": "bid_update",
                "ride_id": str(ride.id),
                "bid": serializer.validated_data['amount']
            }
        )
        
        return Response(RideSerializer(ride).data)

    @action(detail=True, methods=['post'], url_path='accept-bid/(?P<bid_index>\d+)')
    def accept_bid(self, request, pk=None, bid_index=None):
        ride = self.get_object()
        try:
            bid = ride.driver_proposals[int(bid_index)]
        except (IndexError, TypeError):
            return Response({"error": "Invalid bid index"},
                          status=status.HTTP_400_BAD_REQUEST)
        
        ride.accepted_proposal = bid
        ride.status = 'accepted'
        ride.driver = User.objects.get(id=bid['driver'])
        ride.final_fare = bid['amount']
        ride.save()

        # Notify both parties
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f"ride_{ride.id}", {
                "type": "ride_update",
                "message": json.dumps(RideSerializer(ride).data)
            }
        )
        
        return Response(RideSerializer(ride).data)
        
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
