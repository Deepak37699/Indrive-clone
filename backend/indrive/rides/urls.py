from django.urls import path
from .views import RideRequestView, RiderRideListView, DriverRideListView, RideDetailView

urlpatterns = [
    path('request/', RideRequestView.as_view(), name='ride_request'),
    path('rider/list/', RiderRideListView.as_view(), name='rider_ride_list'),
    path('driver/list/', DriverRideListView.as_view(), name='driver_ride_list'),
    path('<int:pk>/', RideDetailView.as_view(), name='ride_detail'),
]
