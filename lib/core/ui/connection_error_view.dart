import 'package:flutter/material.dart';

/// Calm, reusable "couldn't load" / "you're offline" state with a Retry action.
/// Use it in a screen body when an initial data load fails — instead of an
/// alarming dialog or a misleading empty state ("no venues found").
class ConnectionErrorView extends StatelessWidget {
  const ConnectionErrorView({
    super.key,
    required this.onRetry,
    this.offline = false,
    this.title,
    this.message,
    this.retrying = false,
  });

  final VoidCallback onRetry;
  final bool offline;
  final String? title;
  final String? message;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolvedTitle =
        title ?? (offline ? 'You\'re offline' : 'Couldn\'t load this');
    final resolvedMessage = message ??
        (offline
            ? 'Check your connection and try again.'
            : 'Something interrupted the connection. Please try again.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                offline
                    ? Icons.wifi_off_rounded
                    : Icons.cloud_off_rounded,
                size: 30,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              resolvedTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              resolvedMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: retrying ? null : onRetry,
              icon: retrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(retrying ? 'Retrying…' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
