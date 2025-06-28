import random
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken
from .models import User
from .serializers import SendOTPSerializer, VerifyOTPSerializer, UserSerializer
from django.core.cache import cache # Import cache

class SendOTPView(APIView):
    def post(self, request):
        serializer = SendOTPSerializer(data=request.data)
        if serializer.is_valid():
            phone_number = serializer.validated_data['phone_number']
            otp = str(random.randint(100000, 999999))
            cache.set(phone_number, otp, 300) # Store OTP in cache for 5 minutes
            print(f"OTP for {phone_number}: {otp}") # For development purposes
            return Response({'message': 'OTP sent successfully.'}, status=status.HTTP_200_OK)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

from rest_framework.permissions import IsAuthenticated

class VerifyOTPView(APIView):
    def post(self, request):
        serializer = VerifyOTPSerializer(data=request.data)
        if serializer.is_valid():
            phone_number = serializer.validated_data['phone_number']
            otp = serializer.validated_data['otp']
            print(f"Attempting to verify: Phone={phone_number}, OTP={otp}")
            print(f"Cached OTP for {phone_number}: {cache.get(phone_number)}")

            if cache.get(phone_number) == otp:
                # OTP is correct, remove it from cache
                cache.delete(phone_number)

                try:
                    user = User.objects.get(phone_number=phone_number)
                    # If user exists, update last login and generate tokens
                except User.DoesNotExist:
                    # If user does not exist, create a new one
                    # For MVP, default role to 'rider'. User can change later.
                    user = User.objects.create_user(phone_number=phone_number, role='rider')

                refresh = RefreshToken.for_user(user)
                return Response({
                    'refresh': str(refresh),
                    'access': str(refresh.access_token),
                    'user': UserSerializer(user).data
                }, status=status.HTTP_200_OK)
            else:
                return Response({'detail': 'Invalid OTP.'}, status=status.HTTP_400_BAD_REQUEST)
        print(f"Serializer errors: {serializer.errors}") # Add this line
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class UserProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

    def patch(self, request):
        # Allow updating the role
        serializer = UserSerializer(request.user, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
