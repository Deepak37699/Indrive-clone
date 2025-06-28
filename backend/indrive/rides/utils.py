import googlemaps
from django.conf import settings

def get_human_readable_address(latitude, longitude):
    gmaps = googlemaps.Client(key=settings.GOOGLE_MAPS_API_KEY)
    try:
        reverse_geocode_result = gmaps.reverse_geocode((latitude, longitude))
        if reverse_geocode_result:
            # Return the formatted address of the first result
            return reverse_geocode_result[0]['formatted_address']
        else:
            return "Address not found"
    except Exception as e:
        print(f"Error during reverse geocoding: {e}")
        return "Geocoding error"

def calculate_eta(origin_lat, origin_lng, dest_lat, dest_lng):
    """Calculate ETA and distance using Google Maps Directions API"""
    gmaps = googlemaps.Client(key=settings.GOOGLE_MAPS_API_KEY)
    
    try:
        now = datetime.now()
        directions = gmaps.directions(
            (origin_lat, origin_lng),
            (dest_lat, dest_lng),
            mode="driving",
            departure_time=now,
            traffic_model="best_guess"
        )
        
        if directions:
            leg = directions[0]['legs'][0]
            return {
                'eta': leg['duration_in_traffic']['value'] // 60,  # minutes
                'distance': leg['distance']['value'] / 1000,  # kilometers
                'polyline': directions[0]['overview_polyline']['points']
            }
        return None
    except Exception as e:
        print(f"ETA calculation failed: {e}")
        return None
