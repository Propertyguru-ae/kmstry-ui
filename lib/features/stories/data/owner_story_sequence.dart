import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../content_moderation/data/pending_public_media.dart';
import '../../venue_stories/data/venue_story_repository.dart';
import 'story_model.dart';
import 'story_repository.dart';

/// One private owner's sequence: published stories first, local uploads last.
/// Upload receipt changes never change a local entry's navigation identity.
class OwnerStorySequence extends ChangeNotifier {
  OwnerStorySequence({
    required this.kind,
    required List<StoryItem> published,
    this.venueId,
    PendingPublicMediaService? uploads,
    Future<List<StoryItem>> Function()? loadPublished,
  }) : assert(
         kind == PendingPublicMediaKind.personalStory ||
             (kind == PendingPublicMediaKind.venueStory && venueId != null),
       ),
       uploads = uploads ?? PendingPublicMediaService.instance,
       _published = published.where((s) => !s.isUploadingPlaceholder).toList(),
       _loadPublished = loadPublished {
    _session = this.uploads.sessionGeneration;
    this.uploads.changes.addListener(_sync);
    _sync();
  }

  final PendingPublicMediaKind kind;
  final String? venueId;
  final PendingPublicMediaService uploads;
  final Future<List<StoryItem>> Function()? _loadPublished;
  late final int _session;
  List<StoryItem> _published;
  Map<String, PendingPublicMedia> _pending = {};
  final Set<String> _deleted = {};
  Timer? _retry;
  bool _loading = false;
  bool _disposed = false;
  bool get sessionValid => uploads.isCurrentSession(_session);

  PendingPublicMedia? pendingFor(StoryItem story) =>
      _pending[story.ownerUploadId];

  List<StoryItem> get stories {
    if (!sessionValid) return [];
    final pending = _pending.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [
      ..._published.where((s) => !_deleted.contains(s.id)),
      for (final item in pending)
        StoryItem(
          id: 'owner-upload:${item.uploadId ?? item.id}',
          ownerUploadId: item.uploadId ?? item.id,
          mediaUrl: '', // No unsigned/private URL can enter public rendering.
          mediaType: item.isVideo ? 'video' : 'photo',
          createdAt: item.createdAt,
          expiresAt: item.createdAt.add(const Duration(hours: 24)),
          isVenueStory: kind == PendingPublicMediaKind.venueStory,
          textOverlay: item.textOverlay,
        ),
    ];
  }

  void removePublished(String id) {
    _deleted.add(id);
    _published.removeWhere((s) => s.id == id);
  }

  void removeCancelledUpload(String key, String receiptId) {
    if (_disposed) return;
    _deleted.add(receiptId);
    _published.removeWhere((story) => story.id == receiptId);
    _pending.remove(key);
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    if (!sessionValid) {
      _pending.clear();
      _published.clear();
      _retry?.cancel();
      notifyListeners();
      return;
    }
    final publicIds = _published.map((s) => s.id).toSet();
    final next = <String, PendingPublicMedia>{
      for (final item in uploads.forKind(kind, venueId: venueId))
        if (!publicIds.contains(item.id) && !_deleted.contains(item.id))
          (item.uploadId ?? item.id): item,
    };
    // The tracker removes a published job before screens reload canonical
    // stories. Retain its owner preview until that exact public ID is fetched.
    for (final entry in _pending.entries) {
      if (!next.containsKey(entry.key) &&
          !_deleted.contains(entry.value.id) &&
          !publicIds.contains(entry.value.id) &&
          uploads.wasPublished(entry.value.id)) {
        next[entry.key] = entry.value.withState(
          // wasPublished is set only after the tracker confirms the exact ID
          // on the public endpoint, not merely after an APPROVED decision.
          PendingPublicMediaState.published,
        );
      }
    }
    _pending = next;
    notifyListeners();
    if (_pending.values.any((item) => uploads.wasPublished(item.id))) {
      unawaited(_refreshPublished());
    }
  }

  Future<List<StoryItem>> _fetch() async {
    if (_loadPublished != null) return _loadPublished();
    if (kind == PendingPublicMediaKind.personalStory) {
      return StoryRepository().getMyStories();
    }
    final stories = await VenueStoryRepository().getVenueStories(venueId!);
    return stories
        .map(
          (s) => StoryItem(
            id: s.id,
            mediaUrl: s.mediaUrl,
            mediaType: s.mediaType,
            thumbnailUrl: s.thumbnailUrl,
            durationSecs: s.durationSecs,
            mediaReference: s.mediaReference,
            textOverlay: s.textOverlay,
            expiresAt: s.expiresAt,
            createdAt: s.createdAt,
            viewedByMe: s.viewedByMe,
            viewCount: s.viewCount,
            canViewStats: s.canViewStats,
            isVenueStory: true,
            venueId: venueId,
            user: s.posterUserId == null
                ? null
                : StoryUser(id: s.posterUserId!),
          ),
        )
        .toList();
  }

  Future<void> _refreshPublished() async {
    if (_loading || _retry?.isActive == true || _disposed || !sessionValid) {
      return;
    }
    _loading = true;
    try {
      final fresh = await _fetch();
      if (_disposed || !sessionValid) return;
      _published = fresh.where((s) => !_deleted.contains(s.id)).toList();
    } catch (_) {
      // Do not claim publication or lose the preview after a failed fetch.
    } finally {
      _loading = false;
    }
    if (_disposed || !sessionValid) return;
    // Bound retries and keep them owned by this route, never per upload.
    _retry = Timer(const Duration(seconds: 5), () {
      if (!_disposed) _sync();
    });
    _sync();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    uploads.changes.removeListener(_sync);
    super.dispose();
  }
}
