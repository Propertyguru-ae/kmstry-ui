import 'package:flutter/material.dart';

/// Menü kategorileri — backend `VenueMenuCategory` enum'ıyla birebir eşleşir.
enum VenueMenuCategory {
  breakfast,
  starter,
  main,
  dessert,
  drink,
  snack,
  other,
}

extension VenueMenuCategoryExt on VenueMenuCategory {
  String get apiValue {
    switch (this) {
      case VenueMenuCategory.breakfast:
        return 'BREAKFAST';
      case VenueMenuCategory.starter:
        return 'STARTER';
      case VenueMenuCategory.main:
        return 'MAIN';
      case VenueMenuCategory.dessert:
        return 'DESSERT';
      case VenueMenuCategory.drink:
        return 'DRINK';
      case VenueMenuCategory.snack:
        return 'SNACK';
      case VenueMenuCategory.other:
        return 'OTHER';
    }
  }

  String get label {
    switch (this) {
      case VenueMenuCategory.breakfast:
        return 'Breakfast';
      case VenueMenuCategory.starter:
        return 'Starters';
      case VenueMenuCategory.main:
        return 'Mains';
      case VenueMenuCategory.dessert:
        return 'Desserts';
      case VenueMenuCategory.drink:
        return 'Drinks';
      case VenueMenuCategory.snack:
        return 'Snacks';
      case VenueMenuCategory.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case VenueMenuCategory.breakfast:
        return Icons.free_breakfast_outlined;
      case VenueMenuCategory.starter:
        return Icons.tapas_outlined;
      case VenueMenuCategory.main:
        return Icons.restaurant_outlined;
      case VenueMenuCategory.dessert:
        return Icons.icecream_outlined;
      case VenueMenuCategory.drink:
        return Icons.local_bar_outlined;
      case VenueMenuCategory.snack:
        return Icons.bakery_dining_outlined;
      case VenueMenuCategory.other:
        return Icons.restaurant_menu_outlined;
    }
  }

  static VenueMenuCategory fromApi(String? raw) {
    for (final c in VenueMenuCategory.values) {
      if (c.apiValue == raw) return c;
    }
    return VenueMenuCategory.other;
  }
}

/// Kategori seçimi/gruplaması için ekranda kullanılan sabit sıra.
const List<VenueMenuCategory> kVenueMenuCategoryOrder = [
  VenueMenuCategory.breakfast,
  VenueMenuCategory.starter,
  VenueMenuCategory.main,
  VenueMenuCategory.dessert,
  VenueMenuCategory.drink,
  VenueMenuCategory.snack,
  VenueMenuCategory.other,
];

class VenueMenuItem {
  final String id;
  final String venueId;
  final VenueMenuCategory category;
  final String title;
  final String? description;
  final double? price;
  final String currency;
  final List<String> photos;
  final int sortOrder;

  const VenueMenuItem({
    required this.id,
    required this.venueId,
    required this.category,
    required this.title,
    this.description,
    this.price,
    this.currency = 'AED',
    this.photos = const [],
    this.sortOrder = 0,
  });

  factory VenueMenuItem.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'];
    final photos = <String>[];
    if (rawPhotos is List) {
      for (final p in rawPhotos) {
        if (p is Map && p['url'] != null) {
          photos.add(p['url'].toString());
        } else if (p is String) {
          photos.add(p);
        }
      }
    }
    final rawPrice = json['price'];
    return VenueMenuItem(
      id: json['id']?.toString() ?? '',
      venueId: json['venueId']?.toString() ?? '',
      category: VenueMenuCategoryExt.fromApi(json['category']?.toString()),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      price: rawPrice == null
          ? null
          : (rawPrice is num
                ? rawPrice.toDouble()
                : double.tryParse(rawPrice.toString())),
      currency: json['currency']?.toString() ?? 'AED',
      photos: photos,
      sortOrder: json['sortOrder'] is int
          ? json['sortOrder'] as int
          : int.tryParse(json['sortOrder']?.toString() ?? '') ?? 0,
    );
  }

  /// "₺120,00" gibi görsel bir fiyat etiketi (fiyat yoksa null).
  String? get priceLabel {
    if (price == null) return null;
    final symbol = _currencySymbol(currency);
    final value = price!;
    final formatted = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return '$symbol$formatted';
  }

  static String _currencySymbol(String code) => menuCurrencySymbol(code);
}

/// Menü fiyatında seçilebilen para birimi.
class MenuCurrency {
  final String code;
  final String symbol;
  final String label;
  const MenuCurrency(this.code, this.symbol, this.label);
}

/// Fiyat eklerken seçilebilen para birimleri (TL, dolar, euro, sterlin, dirhem).
const List<MenuCurrency> kMenuCurrencies = [
  MenuCurrency('TRY', '₺', 'Turkish Lira'),
  MenuCurrency('USD', '\$', 'US Dollar'),
  MenuCurrency('EUR', '€', 'Euro'),
  MenuCurrency('GBP', '£', 'British Pound'),
  MenuCurrency('AED', 'د.إ', 'UAE Dirham'),
];

String menuCurrencySymbol(String code) {
  for (final c in kMenuCurrencies) {
    if (c.code == code.toUpperCase()) return c.symbol;
  }
  return '$code ';
}
