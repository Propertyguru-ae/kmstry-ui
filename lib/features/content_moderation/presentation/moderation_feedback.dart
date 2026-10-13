import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';

void showModerationQueuedFeedback(
  BuildContext context, {
  String subject = 'Upload',
}) {
  showSuccessSnackBar(
    context,
    message: '$subject received. It will appear after the content check.',
    icon: Icons.verified_user_outlined,
    duration: const Duration(seconds: 4),
  );
}
