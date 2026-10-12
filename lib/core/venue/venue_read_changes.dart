import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

enum VenueReadSection { identity, events, partnerships }

class VenueReadChange {
  const VenueReadChange(this.venueId, this.sections, this.session);
  final String venueId;
  final Set<VenueReadSection> sections;
  final int session;
}

/// Successful metadata writes invalidate only their venue and current login.
/// Media still uses the existing publication signals, never upload progress.
class VenueReadChanges {
  static final changes = ValueNotifier<VenueReadChange?>(null);

  static void committed(
    String venueId,
    Set<VenueReadSection> sections,
    int session,
  ) {
    if (venueId.isEmpty ||
        !PendingPublicMediaService.instance.isCurrentSession(session)) {
      return;
    }
    changes.value = VenueReadChange(
      venueId,
      Set.unmodifiable(sections),
      session,
    );
  }
}
