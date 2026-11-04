import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/app_confirmation_dialog.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/people/data/friendship_changes.dart';

/// Profil, Friends ve mesajların paylaştığı engelleme akışı: kırmızı onay, istek,
/// sonuç kartı. [onConfirmed] onaydan hemen sonra, istek başlamadan çağrılır.
/// Kişi engellendiyse `true` döner.
Future<bool> confirmAndBlockUser(
  BuildContext context, {
  required CheckinRepository repository,
  required String targetUserId,
  VoidCallback? onConfirmed,
}) async {
  final confirmed = await showDestructiveConfirmationDialog(
    context,
    title: 'Block this user?',
    message:
        'You will no longer be able to message each other. Your chat history will stay available. You can unblock this person in Settings → Blocked users.',
    confirmLabel: 'Block user',
    icon: Icons.block_rounded,
  );
  if (!confirmed || !context.mounted) return false;
  onConfirmed?.call();
  try {
    await repository.blockUser(targetUserId);
  } catch (error) {
    if (context.mounted) {
      showBrandedNotice(
        context,
        title: 'Could not block user',
        message: _isTooManyRequests(error)
            ? 'Please wait a moment before trying again.'
            : 'Please try again.',
        tone: BrandedNoticeTone.error,
      );
    }
    return false;
  }
  // Backend engellenenleri listelemez; liste, sohbet ve sayaçlar da güncellensin.
  FriendshipChanges.changed(targetUserId, active: false);
  if (context.mounted) {
    showBrandedNotice(
      context,
      title: 'User blocked',
      message: 'You can unblock them in Settings → Blocked users.',
      tone: BrandedNoticeTone.success,
      icon: Icons.block_rounded,
      duration: const Duration(seconds: 4),
    );
  }
  return true;
}

/// Engeli kaldırma yıkıcı değildir: mavi onay, istek, sonuç kartı. [onConfirmed]
/// onaydan hemen sonra çağrılır. Kaldırıldıysa `true` döner.
Future<bool> confirmAndUnblockUser(
  BuildContext context, {
  required CheckinRepository repository,
  required String targetUserId,
  VoidCallback? onConfirmed,
}) async {
  final confirmed = await showAppConfirmationDialog(
    context,
    title: 'Unblock this user?',
    message:
        'If you unblock this person, you may be able to see each other again in the app and continue messaging.',
    confirmLabel: 'Unblock',
    icon: Icons.lock_open_rounded,
  );
  if (!confirmed || !context.mounted) return false;
  onConfirmed?.call();
  try {
    await repository.unblockUser(targetUserId);
  } catch (error) {
    if (context.mounted) {
      showBrandedNotice(
        context,
        title: 'Could not unblock user',
        message: _isTooManyRequests(error)
            ? 'Please wait a moment before trying again.'
            : 'Please try again.',
        tone: BrandedNoticeTone.error,
      );
    }
    return false;
  }
  FriendshipChanges.refresh();
  if (context.mounted) {
    showBrandedNotice(
      context,
      title: 'User unblocked',
      message: 'You may now see each other again and continue messaging.',
      tone: BrandedNoticeTone.success,
      icon: Icons.lock_open_rounded,
      duration: const Duration(seconds: 4),
    );
  }
  return true;
}

bool _isTooManyRequests(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('too many requests') ||
      text.contains('throttlerexception') ||
      text.contains('429');
}
