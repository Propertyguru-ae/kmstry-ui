import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';

Future<bool> confirmRemoveFriend(
  BuildContext context,
  String name,
) => showDestructiveConfirmationDialog(
  context,
  title: 'Remove friend?',
  message:
      'Remove $name from your friends? Your chat history will stay available, but you won’t be able to message each other until you both choose Interested again. They won’t be notified.',
  confirmLabel: 'Remove friend',
  icon: Icons.person_remove_outlined,
);

void showFriendRemovedNotice(BuildContext context) => showBrandedNotice(
  context,
  title: 'Friend removed',
  message: 'You can connect again if you both choose Interested.',
  tone: BrandedNoticeTone.success,
  icon: Icons.person_remove_outlined,
  duration: const Duration(seconds: 4),
);

void showRemoveFriendFailedNotice(BuildContext context) => showBrandedNotice(
  context,
  title: 'Could not remove friend',
  message: 'Refresh and try again.',
  tone: BrandedNoticeTone.error,
);
