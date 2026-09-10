import 'venue_model.dart';

final dummyVenues = List.generate(
  10,
  (i) => Venue(
    id: '$i',
    name: 'Venue ${i + 1}',
    type: 'Event',
    status: 'Getting busy',
    address: 'DIFC Gate Village ${i + 1}',
    city: 'Dubai',
    photoUrl: '', // şimdilik boş
    latitude: 25.2048,
    longitude: 55.2708,
    tag: 'Late night crowd',
  ),
);
