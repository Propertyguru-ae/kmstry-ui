import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

enum EventDeleteScope { single, series }

Future<EventDeleteScope?> confirmEventDeletion(
  BuildContext context,
  VenueUpcomingEvent event,
) async {
  final scope = event.isRecurring
      ? await showModalBottomSheet<EventDeleteScope>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => const _EventDeleteScopeSheet(),
        )
      : EventDeleteScope.single;
  if (scope == null || !context.mounted) return null;
  final series = scope == EventDeleteScope.series;
  final confirmed = await showDestructiveConfirmationDialog(
    context,
    icon: Icons.event_busy_rounded,
    title: series ? 'Delete this series?' : 'Delete this event?',
    message: series
        ? 'All past and future events in this series will be permanently deleted. This can’t be undone.'
        : '“${event.title}” will be permanently deleted. ${event.isRecurring ? 'Other events in this series will be kept. ' : ''}This can’t be undone.',
    confirmLabel: series ? 'Delete series' : 'Delete event',
  );
  return confirmed ? scope : null;
}

String eventDeletionError(Object error) {
  if (error is ApiException && error.data['errorCode'] == 'EVENT_HAS_TICKETS') {
    return 'This event or series has tickets and cannot be deleted. A separate cancellation/refund process is required.';
  }
  if (error is ApiException && error.statusCode == 409) {
    return 'This event changed. Refresh it and try again.';
  }
  return 'Could not delete event. Refresh it and try again.';
}

class _EventDeleteScopeSheet extends StatelessWidget {
  const _EventDeleteScopeSheet();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final dim = dark ? const Color(0xFF8EA0BA) : const Color(0xFF4F5D6D);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0D1525) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: dim.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Delete recurring event',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: text,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Which events do you want to delete?',
                style: TextStyle(fontSize: 13, color: dim),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.event_outlined,
                color: Color(0xFFF08838),
              ),
              title: Text('Only this event', style: TextStyle(color: text)),
              subtitle: Text(
                'Just this occurrence',
                style: TextStyle(color: dim),
              ),
              onTap: () => Navigator.pop(context, EventDeleteScope.single),
            ),
            ListTile(
              leading: const Icon(
                Icons.repeat_rounded,
                color: Color(0xFFEF4444),
              ),
              title: Text(
                'All events in series',
                style: TextStyle(color: text),
              ),
              subtitle: Text(
                'All past and future occurrences',
                style: TextStyle(color: dim),
              ),
              onTap: () => Navigator.pop(context, EventDeleteScope.series),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
