import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:permission_handler/permission_handler.dart';

class CheckInPage extends StatefulWidget {
  final String venueId;

  const CheckInPage({super.key, required this.venueId});
  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _vibeController = TextEditingController();

  // Birden fazla fotoğrafı tutmak için liste yapısı
  final List<XFile> _photos = [];
  final int _maxPhotos = 2;
  final _repo = CheckinRepository();
  bool _isSubmitting = false;

  // Öne çıkarılan fotoğrafın indeksi (varsayılan olarak ilk fotoğraf)
  int _featuredIndex = 0;

  Future<bool> _ensureCameraPermission() async {
    final result = await Permission.camera.request();

    debugPrint('📸 Camera permission result: $result');

    if (result.isGranted) return true;

    if (result.isPermanentlyDenied) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Camera access required'),
          content: const Text(
            'Please enable camera access from Settings to take photos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
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

    return false;
  }

  Future<void> _pickImage() async {
    if (_photos.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can add up to 2 photos.")),
      );
      return;
    }

    // 👇 İZİN BURADA
    final hasPermission = await _ensureCameraPermission();
    if (!hasPermission) return;

    final result = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (result != null) {
      setState(() {
        _photos.add(result);
      });
    }
  }

  /// Fotoğrafı listeden kaldırma
  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
      // Eğer öne çıkan fotoğraf silinirse, seçimi başa döndür
      if (_featuredIndex >= _photos.length) {
        _featuredIndex = 0;
      }
    });
  }

  /// Fotoğrafı öne çıkan olarak işaretleme
  void _setFeatured(int index) {
    setState(() {
      _featuredIndex = index;
    });
  }

  Future<void> _submitCheckin() async {
    if (_photos.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      // 🔴 Şimdilik sabit (sonra GPS’ten gelecek)
      //const venueId = 'dbe83cb4-d108-4b11-b999-f34abbe39825';
      const latitude = 25.2105;
      const longitude = 55.276;

      // 1️⃣ Check-in oluştur
      final checkinId = await _repo.createCheckin(
        venueId: widget.venueId,
        latitude: latitude,
        longitude: longitude,
        vibe: _vibeController.text.trim(),
      );
      ActiveCheckinService().setActiveCheckin(checkinId);

      // 2️⃣ Fotoğrafları yükle
      for (int i = 0; i < _photos.length; i++) {
        await _repo.uploadCheckinPhoto(
          checkinId: checkinId,
          file: File(_photos[i].path),
          isFeatured: i == _featuredIndex,
        );
      }

      // ✅ Başarılı
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Check-in error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Check-in failed')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Check in',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// INFORMATION TEXT
            const Text(
              'Select your featured photo by tapping on it. This will represents you at this venue.',
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),

            /// PHOTOS SECTION
            const Text(
              'Photos',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ...List.generate(_photos.length, (index) {
                  return _buildPhotoBox(
                    index: index,
                    isFeatured: _featuredIndex == index,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(_photos[index].path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  );
                }),

                if (_photos.length < _maxPhotos) _buildAddBox(),
              ],
            ),

            const SizedBox(height: 30),

            /// VIBE SECTION
            const Text(
              'Vibe',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _vibeController,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                FocusScope.of(context).unfocus();
              },
              decoration: InputDecoration(
                hintText: 'Say something that helps people pick up your vibe.',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 40),

            /// CHECK IN BUTTON
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_photos.isEmpty || _isSubmitting)
                    ? null
                    : _submitCheckin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Check in',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// Fotoğraf kutusu tasarımı (Yıldızlı seçim özelliği ile)
  Widget _buildPhotoBox({
    required int index,
    required bool isFeatured,
    required Widget child,
  }) {
    double size = (MediaQuery.of(context).size.width - 64) / 3;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _setFeatured(index),
          child: Container(
            width: size,
            height: size * 1.3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.grey.shade200,
              border: isFeatured
                  ? Border.all(color: Colors.black, width: 2.5)
                  : null,
            ),
            child: child,
          ),
        ),
        // Silme Butonu
        Positioned(
          top: -5,
          right: -5,
          child: GestureDetector(
            onTap: () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
        // Öne Çıkan Yıldız İkonu
        if (isFeatured)
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.star, size: 14, color: Color(0xFFFFD700)),
            ),
          ),
      ],
    );
  }

  /// Yeni fotoğraf ekleme kutusu
  Widget _buildAddBox() {
    double size = (MediaQuery.of(context).size.width - 64) / 3;

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: size,
        height: size * 1.3,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 2),
        ),
        child: Icon(Icons.add, size: 30, color: Colors.grey.shade400),
      ),
    );
  }
}
