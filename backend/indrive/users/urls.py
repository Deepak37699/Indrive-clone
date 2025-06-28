from django.urls import path
from .views import SendOTPView, VerifyOTPView, UserProfileView

urlpatterns = [
    path('send-otp/', SendOTPView.as_view(), name='send_otp'),
    path('verify-otp/', VerifyOTPView.as_view(), name='verify_otp'),
    path('profile/', UserProfileView.as_view(), name='user_profile'),
]
