import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/presentation/app_update_required_page.dart';

class AppUpdateCoordinator {
  AppUpdateCoordinator._();

  static final AppUpdateCoordinator instance = AppUpdateCoordinator._();

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _showing = false;

  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  Future<void> show(Map<String, dynamic> payload) async {
    if (_showing) return;
    _showing = true;

    final update = RequiredAppUpdate.fromJson(payload);
    void open() {
      final navigator = _navigatorKey?.currentState;
      if (navigator == null) {
        _showing = false;
        return;
      }
      navigator.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/app-update-required'),
          builder: (_) => AppUpdateRequiredPage(update: update),
        ),
        (_) => false,
      );
    }

    if (_navigatorKey?.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open());
    } else {
      open();
    }
  }
}

class RequiredAppUpdate {
  const RequiredAppUpdate({
    required this.platform,
    required this.minimumBuild,
    this.currentBuild,
    this.updateUrl,
  });

  final String platform;
  final int minimumBuild;
  final int? currentBuild;
  final String? updateUrl;

  factory RequiredAppUpdate.fromJson(Map<String, dynamic> json) {
    return RequiredAppUpdate(
      platform: json['platform']?.toString().toLowerCase() ?? '',
      currentBuild: _toInt(json['currentBuild']),
      minimumBuild: _toInt(json['minimumBuild']) ?? 0,
      updateUrl: json['updateUrl']?.toString(),
    );
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
