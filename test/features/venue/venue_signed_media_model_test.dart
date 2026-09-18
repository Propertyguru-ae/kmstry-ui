import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

void main() {
  test('Venue uses the signed cover URL and stable refresh reference', () {
    final venue = Venue.fromJson({
      'id': 'venue-1',
      'source': 'db',
      'isInDb': true,
      'name': 'Test Venue',
      'photo': 'https://signed.example/venue.jpg',
      'photo_media_id': 'venue-1:venue-photo',
      'photo_temporary_url': 'https://signed.example/venue.jpg',
      'photo_refresh_path': '/venues/venue-1/photo-url',
      'latitude': 25.2,
      'longitude': 55.3,
    });

    expect(venue.photoUrl, 'https://signed.example/venue.jpg');
    expect(venue.photoReference?.mediaId, 'venue-1:venue-photo');
    expect(venue.photoReference?.canRefresh, isTrue);
  });

  test('Google-only Venue keeps its external photo without refresh', () {
    final venue = Venue.fromJson({
      'placeId': 'google-place-1',
      'source': 'google',
      'isInDb': false,
      'name': 'Google Venue',
      'photo': 'https://maps.googleapis.com/place/photo?ref=1',
      'latitude': 25.2,
      'longitude': 55.3,
    });

    expect(venue.photoUrl, contains('maps.googleapis.com'));
    expect(venue.photoReference?.canRefresh, isFalse);
  });

  test('VenueGalleryItem parses main and thumbnail signed contracts', () {
    final item = VenueGalleryItem.fromJson({
      'id': 'gallery-1',
      'mediaType': 'video',
      'temporary_url': 'https://signed.example/video.mp4',
      'media_id': 'venue-gallery:gallery-1',
      'refresh_path': '/venues/venue-1/gallery/gallery-1/url',
      'thumbnail_temporary_url': 'https://signed.example/thumb.jpg',
      'thumbnail_media_id': 'venue-gallery:gallery-1:thumbnail',
      'thumbnail_refresh_path':
          '/venues/venue-1/gallery/gallery-1/thumbnail-url',
    });

    expect(item.url, 'https://signed.example/video.mp4');
    expect(item.mediaReference?.canRefresh, isTrue);
    expect(item.thumbnailUrl, 'https://signed.example/thumb.jpg');
    expect(item.thumbnailReference?.canRefresh, isTrue);
  });
}
