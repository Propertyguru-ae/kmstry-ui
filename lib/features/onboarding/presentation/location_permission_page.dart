import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationPermissionPage extends StatelessWidget {
  final VoidCallback onNext;

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
    final status = await Permission.locationWhenInUse.status;

    if (status.isGranted) {
      await AuthRepository().updatePermissions({
        'locationPermissionGranted': true,
      });
      onNext();
      return;
    }

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(context);
      return;
    }

    final result = await Permission.locationWhenInUse.request();

    await AuthRepository().updatePermissions({
      'locationPermissionGranted': result.isGranted,
    });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.location_on, size: 72),
            const SizedBox(height: 16),
            const Text(
              'Enable location',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'We use your location to show nearby venues.',
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _requestLocation(context),
                child: const Text('Enable Location'),
              ),
            ),
            /*TextButton(onPressed: onNext, child: const Text('Not now')),*/
          ],
        ),
      ),
    );
  }
}
