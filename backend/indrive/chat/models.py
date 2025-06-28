from django.db import models
from users.models import User
from rides.models import Ride

class ChatMessage(models.Model):
    ride = models.ForeignKey(Ride, on_delete=models.CASCADE, related_name='messages')
    sender = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sent_messages')
    recipient = models.ForeignKey(User, on_delete=models.CASCADE, related_name='received_messages')
    message = models.TextField()
    timestamp = models.DateTimeField(auto_now_add=True)
    is_read = models.BooleanField(default=False)

    class Meta:
        ordering = ['timestamp']
        indexes = [
            models.Index(fields=['ride', 'timestamp']),
            models.Index(fields=['sender', 'recipient'])
        ]

    def __str__(self):
        return f"{self.sender} to {self.recipient}: {self.message[:20]}"