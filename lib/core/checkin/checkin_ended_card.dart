import 'package:flutter/material.dart';

class CheckinEndedCard extends StatelessWidget {
  const CheckinEndedCard({
    super.key,
    required this.onCheckin,
    required this.onDismiss,
    this.busy = false,
  });
  final VoidCallback onCheckin;
  final VoidCallback onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 6,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Your check-in has ended.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text('Still here? Start a new check-in.'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : onCheckin,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Check in again'),
          ),
        ],
      ),
    ),
  );
}
