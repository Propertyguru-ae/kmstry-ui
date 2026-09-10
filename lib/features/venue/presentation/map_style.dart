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
  {"elementType":"geometry","stylers":[{"color":"#11131a"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#918d9f"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0a0b11"},{"weight":2}]},

  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#363040"}]},
  {"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#595064"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#c7c1d0"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#ddd7e5"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill","stylers":[{"color":"#8e8798"}]},

  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#12141a"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#171820"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#11171a"}]},

  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#191720"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#817b8a"}]},
  {"featureType":"poi.business","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#10221f"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#668b80"}]},
  {"featureType":"poi.sports_complex","elementType":"geometry","stylers":[{"color":"#14211f"}]},

  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#28272e"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#0d0e13"},{"weight":0.7}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#7d7885"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#111218"},{"weight":2}]},
  {"featureType":"road.local","elementType":"geometry","stylers":[{"color":"#222229"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#35313a"}]},
  {"featureType":"road.arterial","elementType":"geometry.stroke","stylers":[{"color":"#1c1922"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#514432"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#8b6840"},{"weight":0.65}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b9a98f"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#5a3d49"}]},

  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#211d29"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},

  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#07151b"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#426b73"}]}
]
''';

/// Açık tema — saf beyaz yerine inci grisi, lavanta ve şampanya
/// tonlarıyla premium "gündüz" harita. KMSTRY pinleri ana odak olarak kalır.
const String kKmstryMapStyleLight = '''
[
  {"elementType":"geometry","stylers":[{"color":"#ebecef"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#66616d"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f2f1f3"},{"weight":2}]},

  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#c7c4cc"}]},
  {"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#aaa5b1"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#45404d"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#37323f"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill","stylers":[{"color":"#77717f"}]},

  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#e9e9ed"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#e0dfe5"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#e6ebe8"}]},

  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#e3e0e7"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#77717f"}]},
  {"featureType":"poi.business","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#cfe0d7"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#587467"}]},
  {"featureType":"poi.sports_complex","elementType":"geometry","stylers":[{"color":"#c5d9d2"}]},
  {"featureType":"poi.sports_complex","elementType":"geometry.stroke","stylers":[{"color":"#9ebeb3"},{"weight":0.7}]},
  {"featureType":"poi.sports_complex","elementType":"labels.text.fill","stylers":[{"color":"#4f7065"}]},

  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#f8f7f8"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#d5d2d9"},{"weight":0.65}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#817b87"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#f8f7f8"},{"weight":2}]},
  {"featureType":"road.local","elementType":"geometry","stylers":[{"color":"#f3f2f4"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ddd9e1"}]},
  {"featureType":"road.arterial","elementType":"geometry.stroke","stylers":[{"color":"#c8c2cd"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#d8c09b"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#b89161"},{"weight":0.55}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#705d47"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#d9bdc7"}]},

  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#dcd8e1"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},

  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#c5dce1"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#587982"}]}
]
''';
