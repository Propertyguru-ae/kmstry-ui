import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';

/// Bir fotoğrafı kare (1:1) avatar olarak kırpma yardımcısı. Kullanıcı pan/zoom
/// ile istediği bölgeyi kareye getirir; sonuç sıkıştırılmış JPEG dosyası olarak
/// döner. İptal edilirse null döner.
///
/// Avatar her yerde daire/kare içinde gösterildiği için oran 1:1 kilitlidir.
Future<File?> cropSquareAvatar(
  BuildContext context,
  File source, {
  Color? toolbarColor,
}) async {
  final theme = Theme.of(context);
  final primary = toolbarColor ?? theme.colorScheme.primary;

  final cropped = await ImageCropper().cropImage(
    sourcePath: source.path,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 90,
    maxWidth: 1024,
    maxHeight: 1024,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Adjust avatar',
        toolbarColor: primary,
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: primary,
        lockAspectRatio: true,
        hideBottomControls: false,
        initAspectRatio: CropAspectRatioPreset.square,
      ),
      IOSUiSettings(
        title: 'Adjust avatar',
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        rotateButtonsHidden: false,
        aspectRatioPickerButtonHidden: true,
      ),
    ],
  );

  if (cropped == null) return null;
  return File(cropped.path);
}

/// Uzaktaki (URL) bir featured foto'yu avatar için yeniden kırpma akışı: indir →
/// kare kırp → `POST /checkins/:id/avatar` ile yükle. Yeni avatar URL'ini döner;
/// kullanıcı iptal ederse veya indirme başarısızsa null döner.
Future<String?> recropCheckinAvatarFromUrl(
  BuildContext context, {
  required String checkinId,
  required String featuredUrl,
}) async {
  if (checkinId.isEmpty || featuredUrl.isEmpty) return null;

  final local = await _downloadToTemp(featuredUrl);
  if (local == null || !context.mounted) return null;

  final cropped = await cropSquareAvatar(context, local);
  if (cropped == null) return null;

  return CheckinRepository().uploadCheckinAvatar(
    checkinId: checkinId,
    file: cropped,
  );
}

Future<File?> _downloadToTemp(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode >= 400) return null;
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/kmstry-avatar-src-${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  } catch (e) {
    log('Avatar source download error: $e');
    return null;
  }
}
