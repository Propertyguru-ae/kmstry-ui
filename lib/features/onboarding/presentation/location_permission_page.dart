import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationPermissionPage extends StatelessWidget {
  final VoidCallback onNext;
  static final LocationPermissionService _locationPermissionService =
      LocationPermissionService();
  static const _bg = AppColors.darkBg;
  static const _brand = AppColors.brand;
  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _pink = AppColors.magentaDark;
  static const _purple = AppColors.brandLight;
  static const _muted = Color(0xFFA6B3D2);
  static const _mutedDim = Color(0xFF7F91B2);

  const LocationPermissionPage({super.key, required this.onNext});

  /*Future<void> _requestLocation(BuildContext context) async {
  final status = await Permission.locationWhenInUse.status;

  if (status.isGranted) {
    onNext();
    return;
  }

  if (status.isPermanentlyDenied) {
    await _showSettingsDialog(context);
    return;
  }

  final result = await Permission.locationWhenInUse.request();

  if (result.isGranted) {
    onNext();
  } else if (result.isDenied || result.isPermanentlyDenied) {
    await _showSettingsDialog(context);
  }
}

*/

  Future<void> _requestLocation(BuildContext context) async {
    final navigator = Navigator.of(context);
    final status = await _locationPermissionService.status();

    if (status.isGranted) {
      await AuthRepository().updatePermissions({
        'locationPermissionGranted': true,
      });
      onNext();
      return;
    }

    if (status.isPermanentlyDenied) {
      await AuthRepository().updatePermissions({
        'locationPermissionGranted': false,
      });
      if (!context.mounted) return;
      await _showSettingsDialog(context);
      if (!navigator.mounted) return;
      onNext();
      return;
    }

    final result = await _locationPermissionService.request();

    await AuthRepository().updatePermissions({
      'locationPermissionGranted': result.isGranted,
    });

    if (!navigator.mounted) return;
    onNext();
  }

  Future<void> _showSettingsDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Location Required'),
        content: const Text(
          'Please enable location access from Settings to discover nearby venues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _notNow(BuildContext context) async {
    final navigator = Navigator.of(context);
    await AuthRepository().updatePermissions({
      'locationPermissionGranted': false,
    });
    if (!navigator.mounted) return;
    onNext();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _bg : const Color(0xFFF7FAFF);
    final heroPrimary = isDark ? Colors.white : AppColors.lightTextPrimary;
    final cardTitle =
        isDark ? const Color(0xFFF4F6FF) : AppColors.lightTextPrimary;
    final textSecondary = isDark ? _muted : AppColors.lightTextSecondary;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : AppColors.lightTextPrimary.withValues(alpha: 0.04);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.lightTextPrimary.withValues(alpha: 0.10);
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned(
            top: -90,
            left: 0,
            right: 0,
            child: Center(
              child: _glow(330, 280, _blue.withValues(alpha: 0.13)),
            ),
          ),
          Positioned(
            bottom: 80,
            right: -70,
            child: _glow(230, 230, _pink.withValues(alpha: 0.09)),
          ),
          Positioned(
            top: 240,
            left: -80,
            child: _glow(230, 230, _brand.withValues(alpha: 0.16)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                children: [
                  const Spacer(flex: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 18,
                        height: 2,
                        decoration: BoxDecoration(
                          color: _pink,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'DISCOVER NEARBY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: _pink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          _brand.withValues(alpha: 0.34),
                          _blue.withValues(alpha: 0.20),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: _purple.withValues(alpha: 0.24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _pink.withValues(alpha: 0.14),
                          blurRadius: 34,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 66,
                      color: _blueBright,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Find your',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 35,
                      height: 1.08,
                      letterSpacing: -0.7,
                      fontWeight: FontWeight.w800,
                      color: heroPrimary,
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_blueBright, _pink],
                    ).createShader(bounds),
                    child: const Text(
                      'local vibe.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 35,
                        height: 1.08,
                        letterSpacing: -0.7,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'KMSTRY uses your location to show nearby venues, people, and moments around you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Explore what is around you',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: cardTitle,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Your location helps us surface nearby venues and check-in activity.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.8,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _infoPill(),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  PrimaryButton(
                    label: 'Enable Location',
                    onPressed: () => _requestLocation(context),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => _notNow(context),
                    style: TextButton.styleFrom(foregroundColor: _mutedDim),
                    child: const Text(
                      'Not now',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: _pink.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _pink.withValues(alpha: 0.28)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: _pink),
          SizedBox(width: 7),
          Text(
            'Used only while you use KMSTRY',
            style: TextStyle(
              color: _pink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double w, double h, Color color) {
    return IgnorePointer(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 0.65],
          ),
        ),
      ),
    );
  }
}
