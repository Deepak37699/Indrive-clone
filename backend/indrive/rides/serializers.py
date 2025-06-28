from rest_framework import serializers
from .models import Ride
from users.serializers import UserSerializer
from .utils import get_human_readable_address

import googlemaps # Import googlemaps for Directions API
from django.conf import settings # Import settings to access API key

class RideSerializer(serializers.ModelSerializer):
    rider = UserSerializer(read_only=True)
    driver = UserSerializer(read_only=True)
    driver_proposals = serializers.JSONField(read_only=True)
    passenger_counter_offers = serializers.JSONField(read_only=True)
    accepted_proposal = serializers.JSONField(read_only=True)

    class Meta:
        model = Ride
        fields = '__all__'
        read_only_fields = ['id', 'rider', 'driver', 'status', 'created_at',
                          'accepted_at', 'completed_at', 'fare', 'route_polyline',
                          'driver_proposals', 'passenger_counter_offers', 'accepted_proposal']

class BidSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=8, decimal_places=2, min_value=1)
    message = serializers.CharField(max_length=200, required=False)

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError("Bid amount must be positive")
        return value

    def create(self, validated_data):
        # Extract LatLngs and convert to human-readable addresses
        pickup_lat = validated_data.get('pickup_latitude')
        pickup_lon = validated_data.get('pickup_longitude')
        destination_lat = validated_data.get('destination_latitude')
        destination_lon = validated_data.get('destination_longitude')

        if pickup_lat is not None and pickup_lon is not None:
            validated_data['pickup_location'] = get_human_readable_address(pickup_lat, pickup_lon)
            validated_data['pickup_latitude'] = pickup_lat
            validated_data['pickup_longitude'] = pickup_lon
        
        if destination_lat is not None and destination_lon is not None:
            validated_data['destination_location'] = get_human_readable_address(destination_lat, destination_lon)
            validated_data['destination_latitude'] = destination_lat
            validated_data['destination_longitude'] = destination_lon

        # Generate route polyline using Google Directions API
        gmaps = googlemaps.Client(key=settings.GOOGLE_MAPS_API_KEY)
        try:
            directions_result = gmaps.directions(
                (pickup_lat, pickup_lon),
                (destination_lat, destination_lon),
                mode="driving"
            )
            if directions_result:
                # The encoded polyline is usually in the first leg of the first route
                encoded_polyline = directions_result[0]['overview_polyline']['points']
                validated_data['route_polyline'] = encoded_polyline
        except Exception as e:
            print(f"Error generating route polyline: {e}")
            validated_data['route_polyline'] = None # Or handle more robustly

        return super().create(validated_data)

    def to_representation(self, instance):
        # Convert model instance to representation (for GET requests)
        representation = super().to_representation(instance)
        # Ensure coordinates are included in representation if needed by frontend
        return representation
