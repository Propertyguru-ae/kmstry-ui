/// KMSTRY marka temalı Google Map stilleri.
///
/// Amaç: harita "Google Maps" gibi görünmesin, KMSTRY kimliğini taşısın ve
/// yalnızca BİZİM venue marker'larımız öne çıksın. Bu yüzden:
///   * Google'ın kendi POI / işletme pin'leri ve etiketleri kapatıldı,
///   * toplu taşıma (transit) kapatıldı,
///   * zemin/su/yol renkleri logo paletine (koyu navy + mavi vurgu) çekildi.
///
/// [GoogleMap.style] parametresine verilir (google_maps_flutter ≥ 2.5).
library;

/// Koyu tema — premium, dikkat çekici "gece" harita.
const String kKmstryMapStyleDark = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0a1020"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8da0bd"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#06091a"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1a2a4a"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#a6b3d2"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#c2cedf"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill","stylers":[{"color":"#6f7f9e"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0d1f1a"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#141d33"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#5d6b7b"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#06091a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#182742"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1e2b4d"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1a9fe8"},{"weight":0.4}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050a18"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#33486a"}]}
]
''';

/// Açık tema — temiz, yumuşak "gündüz" harita (yine Google POI'leri kapalı).
const String kKmstryMapStyleLight = '''
[
  {"elementType":"geometry","stylers":[{"color":"#f2f6fc"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#5d6b7b"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#d9e5f4"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#334155"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#dff0e6"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8298b4"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#f6f9ff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#e6eefc"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1a9fe8"},{"weight":0.25}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9e0f5"}]}
]
''';
