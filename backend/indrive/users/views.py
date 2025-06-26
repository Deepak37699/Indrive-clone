import random
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken
from .models import User
from .serializers import SendOTPSerializer, VerifyOTPSerializer, UserSerializer

# This will store OTPs temporarily. In a real app, use a database or cache.
otp_store = {}

class SendOTPView(APIView):
    def post(self, request):
        serializer = SendOTPSerializer(data=request.data)
        if serializer.is_valid():
            phone_number = serializer.validated_data['phone_number']
            otp = str(random.randint(100000, 999999))
            otp_store[phone_number] = otp
            print(f"OTP for {phone_number}: {otp}") # For development purposes
            return Response({'message': 'OTP sent successfully.'}, status=status.HTTP_200_OK)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class VerifyOTPView(APIView):
    def post(self, request):
        serializer = VerifyOTPSerializer(data=request.data)
        if serializer.is_valid():
            phone_number = serializer.validated_data['phone_number']
            otp = serializer.validated_data['otp']

            if otp_store.get(phone_number) == otp:
                # OTP is correct, remove it from store
                del otp_store[phone_number]

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
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
