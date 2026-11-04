import 'package:flutter/foundation.dart';
import 'match_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/stories/data/story_visibility.dart';

class FriendshipChange {
  const FriendshipChange(this.userId, this.active, [this.friendship]);
  final MatchItem? friendship;
  final String userId;
  final bool active;
}

/// Silent session-local invalidation, never a user notification.
class FriendshipChanges {
  static final changes = ValueNotifier<FriendshipChange?>(null);
  static int revision = 0;

  static void refresh() {
    revision++;
    StoryVisibility.changed('', blocked: false);
    changes.value = FriendshipChange('', false);
  }

  static void changed(
    String userId, {
    required bool active,
    MatchItem? friendship,
  }) {
    if (userId.isEmpty) return;
    revision++;
    ChatMemoryCache.shared.invalidateFriendship(userId);
    StoryVisibility.changed(userId, blocked: !active);
    changes.value = FriendshipChange(userId, active, friendship);
  }
}
