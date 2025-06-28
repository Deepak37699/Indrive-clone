import googlemaps
import math
from django.conf import settings
from datetime import datetime
from users.models import User

def calculate_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in kilometers using Haversine formula"""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat/2) * math.sin(dlat/2) +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon/2) * math.sin(dlon/2))
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c
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

def find_best_drivers(ride):
    """Find optimal drivers using weighted criteria"""
    from django.conf import settings
    from users.models import User
    
    drivers = User.objects.filter(
        is_driver=True,
        is_available=True,
        current_location__isnull=False
    ).exclude(current_location='')[:settings.MAX_DRIVERS_TO_NOTIFY*3]
    
    scored_drivers = []
    for driver in drivers:
        try:
            # Parse driver location
            driver_lat, driver_lng = map(float, driver.current_location.split(','))
            
            # Calculate distance score
            distance_km = calculate_distance(
                driver_lat, driver_lng,
                ride.pickup_latitude, ride.pickup_longitude
            )
            if distance_km > settings.DRIVER_SEARCH_RADIUS_KM:
                continue
                
            # Calculate all scores
            distance_score = 1 / (1 + distance_km)
            rating_score = driver.rating / 5.0
            fare_diff = abs((driver.average_fare or ride.proposed_fare) - ride.proposed_fare)
            fare_score = 1 / (1 + fare_diff)
            response_score = 1 - min(driver.avg_response_time / 300, 1)
            
            # Calculate weighted total
            total_score = (
                settings.RIDE_MATCHING_WEIGHTS['distance'] * distance_score +
                settings.RIDE_MATCHING_WEIGHTS['rating'] * rating_score +
                settings.RIDE_MATCHING_WEIGHTS['fare_competitiveness'] * fare_score +
                settings.RIDE_MATCHING_WEIGHTS['response_time'] * response_score
            )
            
            scored_drivers.append({
                'driver': driver,
                'score': total_score,
                'details': {
                    'distance_km': round(distance_km, 2),
                    'rating': driver.rating,
                    'fare_diff': round(fare_diff, 2),
                    'response_time': driver.avg_response_time
                }
            })
        except Exception as e:
            print(f"Error processing driver {driver.id}: {e}")
    
    return sorted(scored_drivers, key=lambda x: x['score'], reverse=True)[:settings.MAX_DRIVERS_TO_NOTIFY]
