import 'package:flutter/foundation.dart';
import 'story_model.dart';

/// A transient invalidation event, not a persistent/cross-account block cache.
class StoryVisibilityChange {
  final String userId;
  final bool blocked;

  const StoryVisibilityChange(this.userId, {required this.blocked});

  List<StoryGroup> apply(List<StoryGroup> groups) => blocked
      ? groups
            .where(
              (group) => group.venueLabel != null || group.user.id != userId,
            )
            .toList()
      : groups;
}

class StoryVisibility {
  static final changes = ValueNotifier<StoryVisibilityChange?>(null);

  static void changed(String userId, {required bool blocked}) {
    changes.value = StoryVisibilityChange(userId, blocked: blocked);
  }
}
