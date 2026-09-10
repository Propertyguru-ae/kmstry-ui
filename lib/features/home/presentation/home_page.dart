import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import '../../auth/data/auth_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Map<String, dynamic>? _user;
  final LocationPermissionService _locationPermissionService =
      LocationPermissionService();
  bool _loading = true;
  bool _locationGranted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMe();
    _refreshLocationPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocationPermission();
    }
  }

  Future<void> _loadMe() async {
    try {
      final me = await AuthRepository().getMe(); 
      setState(() {
        _user = me;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshLocationPermission() async {
    final status = await _locationPermissionService.status();
    if (!mounted) return;
    setState(() {
      _locationGranted = status.isGranted;
    });
  }

  Future<void> _enableLocationPermission() async {
    final status = await _locationPermissionService.status();
    if (!status.isGranted) {
      await openAppSettings();
      return;
    }
    if (!mounted) return;
    setState(() {
      _locationGranted = status.isGranted;
    });
    try {
      await AuthRepository().updatePermissions({
        'locationPermissionGranted': status.isGranted,
      });
    } catch (_) {}
    if (!status.isGranted) {
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'KMSTRY',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, left: 8.0),
            child: GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, AuthRoutes.profile);
              },
              child: CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                child: Icon(
                  Icons.person_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_locationGranted)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Location permission is off. Enable it to discover nearby venues and people.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _enableLocationPermission,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Enable'),
                  ),
                ],
              ),
            ),
          // 🔔 VERIFY BANNER
          if (_user != null && _user!['email_verified'] == false)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Please verify your email address to unlock all features.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await AuthRepository().resendVerifyEmail();
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: const Text('Verification email sent'),
                          backgroundColor: theme.colorScheme.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Resend'),
                  ),
                ],
              ),
            ),

          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.explore_rounded,
                    size: 80,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome to KMSTRY',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Discover people and moments around you.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
