import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';

class NotificationPermissionPage extends StatefulWidget {
  final VoidCallback onNext;

  const NotificationPermissionPage({super.key, required this.onNext});

  @override
  State<NotificationPermissionPage> createState() =>
      _NotificationPermissionPageState();
}

class _NotificationPermissionPageState
    extends State<NotificationPermissionPage> {
  bool _systemNotificationGranted = false;
  bool _loading = true;

  static const _bg = AppColors.darkBg;
  static const _teal = AppColors.tealDark;
  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _magenta = AppColors.magenta;
  static const _muted = Color(0xFFA6B3D2);
  static const _mutedDim = Color(0xFF7F91B2);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.notification.status;
    _systemNotificationGranted =
        status.isGranted || status == PermissionStatus.provisional;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _enableNotifications() async {
    debugPrint("Notification button pressed");

    // İzin diyaloğunu göster (sistem diyaloğu) — await ile bekle ki kullanıcı
    // "Allow" / "Don't Allow" seçsin, sonra onNext çağrılsın.
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    await SecureStorage.setNotificationOnboardingDone();
    if (!mounted) return;

    widget.onNext();

    // Token kaydı ve backend sync arka planda — UI'ı bloklamaz.
    unawaited(PushManager.instance.handlePermissionFlow());
    unawaited(PushManager.instance.reconcileNotificationState());
  }

  Future<void> _notNow() async {
    // Account-level preference (user opt-out)
    await AuthRepository().updatePermissions({
      'notificationPermissionGranted': false,
    });

    await SecureStorage.setNotificationOnboardingDone();
    widget.onNext();
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

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: _blue)),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Center(
              child: _glow(320, 280, _blue.withValues(alpha: 0.16)),
            ),
          ),
          Positioned(
            bottom: 40,
            right: -60,
            child: _glow(220, 220, _magenta.withValues(alpha: 0.10)),
          ),
          Positioned(
            top: 210,
            left: -70,
            child: _glow(190, 190, _teal.withValues(alpha: 0.13)),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 38),
                      const Spacer(),
                      const SizedBox(width: 38),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
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
                                color: _teal,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'STAY CONNECTED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: _teal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                _blue.withValues(alpha: 0.26),
                                _teal.withValues(alpha: 0.24),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: _teal.withValues(alpha: 0.28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _blue.withValues(alpha: 0.18),
                                blurRadius: 34,
                                offset: const Offset(0, 14),
                              ),
                              BoxShadow(
                                color: _teal.withValues(alpha: 0.16),
                                blurRadius: 26,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            size: 60,
                            color: _blueBright,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Stay',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            height: 1.08,
                            letterSpacing: -0.7,
                            fontWeight: FontWeight.w800,
                            color: heroPrimary,
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_blueBright, _teal],
                          ).createShader(bounds),
                          child: const Text(
                            'connected.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.08,
                              letterSpacing: -0.7,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Get the right updates when someone connects, messages, or shares a moment around you.',
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
                                'Do not miss the vibe',
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
                                'We will only use notifications for important KMSTRY activity.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.8,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _permissionPill(),
                            ],
                          ),
                        ),
                        const Spacer(flex: 2),
                        PrimaryButton(
                          label: 'Enable Notifications',
                          onPressed: _enableNotifications,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _notNow,
                          style: TextButton.styleFrom(
                            foregroundColor: _mutedDim,
                          ),
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
          ),
        ],
      ),
    );
  }

  Widget _permissionPill() {
    final color = _systemNotificationGranted ? _teal : _blueBright;
    final label = _systemNotificationGranted
        ? 'System notifications are on'
        : 'System notifications are off';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _systemNotificationGranted
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
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
