import 'package:flutter/material.dart';

import '../../../core/ui/premium_feedback.dart';

/// Moment kuralları (check-in başına 1 video / 6 Moment) için marka
/// tasarımlı, dostça bilgilendirme — "Something went wrong" hata
/// diyaloğu yerine. Check-in ve profil ekranları aynı metni kullanır.
Future<void> showOneVideoLimitDialog(BuildContext context) =>
    showPremiumPromptDialog(
      context,
      icon: Icons.videocam_rounded,
      title: 'One video per check-in',
      message:
          'You’ve already added a video to this check-in. Snap a photo '
          'instead, or remove your current video to record a new one.',
      confirmLabel: 'Got it',
      showCancel: false,
    );

Future<void> showMomentsFullDialog(BuildContext context) =>
    showPremiumPromptDialog(
      context,
      icon: Icons.photo_library_rounded,
      title: 'Your Moments are full',
      message:
          'You can share up to 6 Moments per check-in. Remove one to make '
          'room for a new Moment.',
      confirmLabel: 'Got it',
      showCancel: false,
    );
