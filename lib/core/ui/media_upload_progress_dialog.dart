import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@immutable
class MediaUploadProgressState {
  const MediaUploadProgressState({
    required this.title,
    required this.message,
    this.progress,
  });

  final String title;
  final String message;
  final double? progress;
}

/// Displays a non-dismissible upload status dialog.
///
/// Media uploads are intentionally kept on the current route: navigating away
/// during a large multipart request can make an otherwise healthy upload look
/// cancelled. Call [update] while preparing/uploading, then [close] in a
/// `finally` block.
class MediaUploadProgressController {
  MediaUploadProgressController({
    required String title,
    required String message,
  }) : _state = ValueNotifier(
         MediaUploadProgressState(title: title, message: message),
       );

  final ValueNotifier<MediaUploadProgressState> _state;
  BuildContext? _dialogContext;
  Future<void>? _dialogFuture;

  Future<void> show(BuildContext context) async {
    final ready = Completer<void>();
    _dialogFuture = showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        _dialogContext = dialogContext;
        if (!ready.isCompleted) {
          scheduleMicrotask(ready.complete);
        }
        return PopScope(
          canPop: false,
          child: _MediaUploadProgressDialog(state: _state),
        );
      },
    );
    await ready.future;
  }

  void update({String? title, String? message, double? progress}) {
    final current = _state.value;
    final normalizedProgress = progress?.clamp(0.0, 1.0).toDouble();
    if (title == null &&
        message == null &&
        normalizedProgress != null &&
        current.progress != null &&
        normalizedProgress < 1 &&
        (normalizedProgress - current.progress!).abs() < 0.01) {
      return;
    }
    _state.value = MediaUploadProgressState(
      title: title ?? current.title,
      message: message ?? current.message,
      progress: normalizedProgress,
    );
  }

  Future<void> close() async {
    final dialogContext = _dialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext, rootNavigator: true).pop();
    }
    await _dialogFuture;
    _dialogContext = null;
    _dialogFuture = null;
  }

  void dispose() => _state.dispose();
}

class _MediaUploadProgressDialog extends StatelessWidget {
  const _MediaUploadProgressDialog({required this.state});

  final ValueListenable<MediaUploadProgressState> state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primary.withValues(alpha: 0.12),
        ),
        child: Icon(
          Icons.cloud_upload_rounded,
          color: colors.primary,
          size: 28,
        ),
      ),
      content: ValueListenableBuilder<MediaUploadProgressState>(
        valueListenable: state,
        builder: (context, value, _) {
          final progress = value.progress;
          final percentage = progress == null ? null : (progress * 100).round();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.68),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: colors.onSurface.withValues(alpha: 0.10),
                ),
              ),
              if (percentage != null) ...[
                const SizedBox(height: 8),
                Text(
                  '$percentage%',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 17,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please keep KMSTRY open and stay on this screen until the upload finishes.',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.55),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
