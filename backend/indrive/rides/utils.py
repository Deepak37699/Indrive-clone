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
