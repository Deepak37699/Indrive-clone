"""
ASGI config for indrive project.

It exposes the ASGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/5.2/howto/deployment/asgi/
"""

import os

from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack
from django.urls import path
from rides.consumers import RideConsumer # We will create this

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'indrive.settings')

application = ProtocolTypeRouter({
    "http": get_asgi_application(),
    "websocket": AuthMiddlewareStack(
        URLRouter([
            path("ws/rides/", RideConsumer.as_asgi()),
        ])
    ),
})
