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

    rider = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='rides_as_rider')
    driver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='rides_as_driver')
    
    pickup_location = models.CharField(max_length=255)
    destination_location = models.CharField(max_length=255)
    
    status = models.CharField(max_length=20, choices=RIDE_STATUS_CHOICES, default='requested')
    
    created_at = models.DateTimeField(auto_now_add=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    
    fare = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    def __str__(self):
        return f"Ride from {self.pickup_location} to {self.destination_location} (Status: {self.status})"
