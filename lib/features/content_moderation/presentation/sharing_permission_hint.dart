import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';

/// The editor owns this state: a declined permission never discards its draft
/// or becomes an upload failure. Real service/session failures still propagate.
class SharingPermissionController extends ChangeNotifier {
  SharingPermissionController({Future<void> Function()? ensure})
    : _ensure = ensure ?? PublicContentPermission.beforePublicSubmit;
  final Future<void> Function() _ensure;
  bool deferred = false;
  bool _disposed = false;

  Future<bool> check() async {
    try {
      await _ensure();
      _setDeferred(false);
      return !_disposed;
    } catch (error) {
      if (!handleDecline(error)) rethrow;
      return false;
    }
  }

  /// Also covers an explicit decline from the request guard after preflight.
  bool handleDecline(Object error) {
    if (!isAwsSharingPermissionDeclined(error)) return false;
    _setDeferred(true);
    return true;
  }

  void _setDeferred(bool value) {
    deferred = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class SharingPermissionHint extends StatelessWidget {
  const SharingPermissionHint({
    super.key,
    required this.controller,
    required this.onReview,
    this.isMedia = false,
    this.message,
  });
  final SharingPermissionController controller;
  final VoidCallback? onReview;
  final bool isMedia;
  final String? message;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.deferred) return const SizedBox.shrink();
      final colors = Theme.of(context).colorScheme;
      return Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message ??
                    (isMedia
                        ? 'Nothing was shared. Allow safety checks to continue.'
                        : 'Your changes haven’t been saved. Allow safety checks to continue.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
              TextButton(
                onPressed: onReview,
                child: const Text('Review permission'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
