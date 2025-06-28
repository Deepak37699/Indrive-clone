from rest_framework import serializers
from .models import Ride
from users.serializers import UserSerializer
from .utils import get_human_readable_address

class RideSerializer(serializers.ModelSerializer):
    rider = UserSerializer(read_only=True)
    driver = UserSerializer(read_only=True)

    # Custom fields for LatLng input
    pickup_latitude = serializers.FloatField(write_only=True, required=False)
    pickup_longitude = serializers.FloatField(write_only=True, required=False)
    destination_latitude = serializers.FloatField(write_only=True, required=False)
    destination_longitude = serializers.FloatField(write_only=True, required=False)

    class Meta:
        model = Ride
        fields = '__all__'
        read_only_fields = ['id', 'rider', 'driver', 'status', 'created_at', 'accepted_at', 'completed_at', 'fare']

    def create(self, validated_data):
        # Extract LatLngs and convert to human-readable addresses
        pickup_lat = validated_data.pop('pickup_latitude', None)
        pickup_lon = validated_data.pop('pickup_longitude', None)
        destination_lat = validated_data.pop('destination_latitude', None)
        destination_lon = validated_data.pop('destination_longitude', None)

        if pickup_lat is not None and pickup_lon is not None:
            validated_data['pickup_location'] = get_human_readable_address(pickup_lat, pickup_lon)
        
        if destination_lat is not None and destination_lon is not None:
            validated_data['destination_location'] = get_human_readable_address(destination_lat, destination_lon)

        return super().create(validated_data)

    def to_representation(self, instance):
        # Convert model instance to representation (for GET requests)
        representation = super().to_representation(instance)
        # You might want to add LatLng back to representation if needed by frontend
        return representation
