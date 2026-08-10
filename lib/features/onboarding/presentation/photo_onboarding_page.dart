import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/permissions_flow_page.dart';

class PhotoOnboardingPage extends StatefulWidget {
  const PhotoOnboardingPage({super.key});

  @override
  State<PhotoOnboardingPage> createState() => _PhotoOnboardingPageState();
}

class _PhotoOnboardingPageState extends State<PhotoOnboardingPage> {
  File? _image;
  final _picker = ImagePicker();

  Future<void> _takePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _goToPermissions() async {
    try {
      if (_image != null) {
        await AuthRepository().uploadProfilePhoto(_image!);
      } else {
        // 👇 SKIP durumu
        await AuthRepository().updateMe({'photo': null});
      }
    } catch (e) {
      debugPrint('Photo onboarding error: $e');
    }

    if (!mounted) return;

    Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a profile photo'),
        actions: [
          TextButton(onPressed: _goToPermissions, child: const Text('Skip')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Add a profile photo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'You can add a photo now or do it later',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            GestureDetector(
              onTap: _takePhoto,
              child: CircleAvatar(
                radius: 64,
                backgroundImage: _image != null ? FileImage(_image!) : null,
                child: _image == null
                    ? const Icon(Icons.camera_alt, size: 40)
                    : null,
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _takePhoto,
              child: const Text('Take photo'),
            ),

            const Spacer(),

            if (_image != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _goToPermissions,
                  child: const Text('Continue'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
