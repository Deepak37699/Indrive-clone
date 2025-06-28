from rest_framework import serializers
from .models import User

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['phone_number', 'role', 'is_available']
        read_only_fields = ['phone_number']

class SendOTPSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=15)

class VerifyOTPSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=15)
    otp = serializers.CharField(max_length=6)
