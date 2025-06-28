from django.urls import path, include
from rest_framework.routers import SimpleRouter
from .views import RideViewSet

router = SimpleRouter()
router.register(r'', RideViewSet, basename='ride')

urlpatterns = [
    path('', include(router.urls)),
]
