import 'package:flutter/material.dart';

Future<void> showPremiumErrorDialog(
  BuildContext context, {
  required String message,
  String title = 'Something went wrong',
  String buttonText = 'OK',
}) async {
  if (!context.mounted) return;
  final colors = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.86),
            height: 1.35,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(buttonText),
          ),
        ],
      );
    },
  );
}
