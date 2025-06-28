from django.db import models
from django.conf import settings

class Ride(models.Model):
    RIDE_STATUS_CHOICES = (
        ('requested', 'Requested'),
        ('accepted', 'Accepted'),
        ('started', 'Started'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled'),
    )
    PROPOSAL_TYPES = (
        ('passenger', 'Passenger Proposal'),
        ('driver', 'Driver Proposal'),
    )

    rider = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='rides_as_rider')
    driver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='rides_as_driver')
    
    pickup_location = models.CharField(max_length=255)
    destination_location = models.CharField(max_length=255)
    
    # Store LatLng coordinates for mapping purposes
    pickup_latitude = models.FloatField(null=True, blank=True)
    pickup_longitude = models.FloatField(null=True, blank=True)
    destination_latitude = models.FloatField(null=True, blank=True)
    destination_longitude = models.FloatField(null=True, blank=True)
    
    status = models.CharField(max_length=20, choices=RIDE_STATUS_CHOICES, default='requested')
    proposal_type = models.CharField(max_length=10, choices=PROPOSAL_TYPES, default='passenger')
    
    created_at = models.DateTimeField(auto_now_add=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    
    proposed_fare = models.DecimalField(max_digits=8, decimal_places=2, default=0.00)
    final_fare = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    eta_minutes = models.IntegerField(null=True, blank=True)
    distance_km = models.FloatField(null=True, blank=True)
    
    # Bidding system fields
    driver_proposals = models.JSONField(default=list)  # Format: [{"driver": id, "amount": decimal, "timestamp": iso8601}]
    passenger_counter_offers = models.JSONField(default=list)  # [{"amount": decimal, "timestamp": iso8601}]
    accepted_proposal = models.JSONField(null=True, blank=True)  # {"type": "driver/passenger", "amount": decimal, "timestamp": iso8601}
    
    # Ride metrics
    distance_km = models.FloatField(null=True, blank=True)
    estimated_duration = models.IntegerField(null=True, blank=True)  # in minutes
    
    # Encoded polyline for the route
    route_polyline = models.TextField(null=True, blank=True)

    def __str__(self):
        return f"Ride from {self.pickup_location} to {self.destination_location} (Status: {self.status})"

class DriverNotification(models.Model):
    driver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    ride = models.ForeignKey('Ride', on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)
    score = models.FloatField()
    details = models.JSONField()
    responded = models.BooleanField(default=False)
    response_time = models.FloatField(null=True)  # Seconds to respond

    class Meta:
        indexes = [
            models.Index(fields=['driver', 'responded']),
            models.Index(fields=['score'])
        ]
