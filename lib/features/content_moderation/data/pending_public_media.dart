import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/performance/performance_diagnostics.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/upload_session_identity.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/public_media_upload_state.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media_store.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';

export 'package:kmstry_frontend/features/content_moderation/data/public_media_upload_state.dart';

enum PendingPublicMediaKind {
  checkinMoment,
  personalStory,
  venueStory,
  venueGallery,
  personalAvatar,
  venueAvatar,
  eventPhoto,
  checkinAvatar,
}

@immutable
class PendingPublicMedia {
  const PendingPublicMedia({
    required this.id,
    required this.kind,
    required this.venueId,
    this.checkinId,
    this.eventId,
    this.recurringRuleId,
    required this.localPath,
    required this.isVideo,
    required this.createdAt,
    this.previewPath,
    this.state = PendingPublicMediaState.checking,
    this.message,
    this.uploadId,
    this.hasServerReceipt = true,
    this.progress,
    this.textOverlay,
  });

  final String id;
  final PendingPublicMediaKind kind;
  final String? venueId;
  final String? checkinId;
  final String? eventId;
  final String? recurringRuleId;
  final String localPath;
  final String? previewPath;
  final bool isVideo;
  final DateTime createdAt;
  final PendingPublicMediaState state;
  final String? message;
  final String? uploadId;
  final bool hasServerReceipt;
  final double? progress;
  final MediaTextOverlay? textOverlay;

  bool get isStory =>
      kind == PendingPublicMediaKind.personalStory ||
      kind == PendingPublicMediaKind.venueStory;

  bool get isAccountAvatar =>
      kind == PendingPublicMediaKind.personalAvatar ||
      kind == PendingPublicMediaKind.venueAvatar;

  bool get isAvatar =>
      isAccountAvatar || kind == PendingPublicMediaKind.checkinAvatar;

  bool get usesExactReceipt =>
      isAvatar || kind == PendingPublicMediaKind.eventPhoto;

  bool belongsToEvent(String venue, String event, String? rule) =>
      kind == PendingPublicMediaKind.eventPhoto &&
      venueId == venue &&
      (eventId == event ||
          (recurringRuleId != null && recurringRuleId == rule));

  String get targetType => switch (kind) {
    PendingPublicMediaKind.checkinMoment => 'CHECKIN_MEDIA',
    PendingPublicMediaKind.personalStory => 'PERSONAL_STORY',
    PendingPublicMediaKind.venueStory => 'VENUE_STORY',
    PendingPublicMediaKind.venueGallery => 'VENUE_GALLERY',
    PendingPublicMediaKind.personalAvatar => 'USER_PROFILE_PHOTO',
    PendingPublicMediaKind.venueAvatar => 'VENUE_COVER',
    PendingPublicMediaKind.eventPhoto => 'EVENT_PHOTO',
    PendingPublicMediaKind.checkinAvatar => 'CHECKIN_AVATAR',
  };

  PendingPublicMedia withState(
    PendingPublicMediaState next, {
    String? reason,
  }) => PendingPublicMedia(
    id: id,
    kind: kind,
    venueId: venueId,
    checkinId: checkinId,
    eventId: eventId,
    recurringRuleId: recurringRuleId,
    localPath: localPath,
    previewPath: previewPath,
    isVideo: isVideo,
    createdAt: createdAt,
    state: next,
    message: reason,
    uploadId: uploadId,
    hasServerReceipt: hasServerReceipt,
    progress: progress,
    textOverlay: textOverlay,
  );

  PendingPublicMedia withPreview(String path) => PendingPublicMedia(
    id: id,
    kind: kind,
    venueId: venueId,
    checkinId: checkinId,
    eventId: eventId,
    recurringRuleId: recurringRuleId,
    localPath: localPath,
    previewPath: path,
    isVideo: isVideo,
    createdAt: createdAt,
    state: state,
    message: message,
    uploadId: uploadId,
    hasServerReceipt: hasServerReceipt,
    progress: progress,
    textOverlay: textOverlay,
  );

  PendingPublicMedia withReceipt(String serverId, {String? resolvedVenueId}) =>
      PendingPublicMedia(
        id: serverId,
        uploadId: uploadId ?? id,
        kind: kind,
        venueId: resolvedVenueId ?? venueId,
        checkinId: checkinId,
        eventId: eventId,
        recurringRuleId: recurringRuleId,
        localPath: localPath,
        previewPath: previewPath,
        isVideo: isVideo,
        createdAt: createdAt,
        textOverlay: textOverlay,
      );

  PendingPublicMedia withProgress(double value) => PendingPublicMedia(
    id: id,
    kind: kind,
    venueId: venueId,
    checkinId: checkinId,
    eventId: eventId,
    recurringRuleId: recurringRuleId,
    localPath: localPath,
    previewPath: previewPath,
    isVideo: isVideo,
    createdAt: createdAt,
    state: state,
    message: message,
    uploadId: uploadId,
    hasServerReceipt: hasServerReceipt,
    progress: value,
    textOverlay: textOverlay,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'kind': kind.name, 'venueId': venueId, 'checkinId': checkinId,
    'eventId': eventId, 'recurringRuleId': recurringRuleId,
    // Only the retained preview is needed after restarting; never persist a
    // camera/video source path as a request that could be replayed.
    'previewPath': previewPath,
    'isVideo': isVideo, 'createdAt': createdAt.toUtc().toIso8601String(),
    'state': state.name, 'message': message, 'uploadId': uploadId,
    'hasServerReceipt': hasServerReceipt,
    'textOverlay': textOverlay?.toJson(),
  };

  static PendingPublicMedia? fromJson(Map<String, dynamic> value) {
    try {
      final id = value['id'] as String;
      if (id.isEmpty) return null;
      return PendingPublicMedia(
        id: id,
        kind: PendingPublicMediaKind.values.byName(value['kind'] as String),
        venueId: value['venueId'] as String?,
        checkinId: value['checkinId'] as String?,
        eventId: value['eventId'] as String?,
        recurringRuleId: value['recurringRuleId'] as String?,
        localPath: '',
        previewPath: value['previewPath'] as String?,
        isVideo: value['isVideo'] as bool,
        createdAt: DateTime.parse(value['createdAt'] as String),
        state: PendingPublicMediaState.values.byName(value['state'] as String),
        message: value['message'] as String?,
        uploadId: value['uploadId'] as String?,
        hasServerReceipt: value['hasServerReceipt'] == true,
        textOverlay: MediaTextOverlay.fromJson(value['textOverlay']),
      );
    } catch (_) {
      return null;
    }
  }
}

typedef PublishedMediaLookup = Future<bool> Function(PendingPublicMedia item);
typedef ModerationLookup =
    Future<MediaModerationSnapshot> Function(PendingPublicMedia item);
typedef StoryUploadCanceller = Future<void> Function(PendingPublicMedia item);
typedef EventPhotoRemover =
    Future<void> Function(
      PendingPublicMedia item,
      bool Function() isCurrentSession,
    );

/// A completed client-error response confirms that this request was rejected.
/// Transport errors and server errors must remain ambiguous, without replay.
class PublicMediaUploadRejected implements Exception {
  const PublicMediaUploadRejected(this.description);
  final String description;
  @override
  String toString() => description;
}

/// Owns transfers and moderation tracking independently of route lifetimes.
/// Persisted records are partitioned by authenticated user and API environment.
/// Public feeds still use only backend-approved media.
class PendingPublicMediaService {
  PendingPublicMediaService._({
    PublishedMediaLookup? publishedLookup,
    ModerationLookup? moderationLookup,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
    PendingPublicMediaStore? store,
    StoryUploadCanceller? cancelStory,
    EventPhotoRemover? removeEventPhoto,
    EventPhotoRemover? removeGalleryPhoto,
  }) : _publishedLookup = publishedLookup ?? _defaultPublishedLookup,
       _moderationLookup = moderationLookup ?? _defaultModerationLookup,
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now,
       _store = store,
       _cancelStory = cancelStory ?? _defaultCancelStory,
       _removeEventPhoto = removeEventPhoto ?? _defaultRemoveEventPhoto,
       _removeGalleryPhoto = removeGalleryPhoto ?? _defaultRemoveGalleryPhoto;

  @visibleForTesting
  PendingPublicMediaService.forTest({
    required PublishedMediaLookup publishedLookup,
    required ModerationLookup moderationLookup,
    required Future<void> Function(Duration) delay,
    DateTime Function()? now,
    PendingPublicMediaStore? store,
    StoryUploadCanceller? cancelStory,
    EventPhotoRemover? removeEventPhoto,
    EventPhotoRemover? removeGalleryPhoto,
  }) : this._(
         publishedLookup: publishedLookup,
         moderationLookup: moderationLookup,
         delay: delay,
         now: now,
         store: store,
         cancelStory: cancelStory,
         removeEventPhoto: removeEventPhoto,
         removeGalleryPhoto: removeGalleryPhoto,
       );

  static final PendingPublicMediaService instance = PendingPublicMediaService._(
    store: DevicePendingPublicMediaStore(),
  );

  final PublishedMediaLookup _publishedLookup;
  final ModerationLookup _moderationLookup;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;
  final PendingPublicMediaStore? _store;
  final StoryUploadCanceller _cancelStory;
  final EventPhotoRemover _removeEventPhoto;
  final EventPhotoRemover _removeGalleryPhoto;
  final Set<String> _removingGalleryPhotos = {};
  final Set<String> _removingEventPhotos = {};
  final Set<String> _cancellingStories = {};
  final Map<String, MultipartUploadCancellation> _storyCancellations = {};
  final Map<String, MultipartUploadCancellation> _eventPhotoCancellations = {};
  final Set<String> _deletedEventTargets = {};

  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  final ValueNotifier<int> publicationChanges = ValueNotifier<int>(0);
  final ValueNotifier<int> avatarPublicationChanges = ValueNotifier<int>(0);
  final ValueNotifier<int> eventPublicationChanges = ValueNotifier<int>(0);
  final Map<String, PendingPublicMedia> _items = {};
  final Set<String> _publishedIds = {};
  int _session = 0;
  String? _scope;
  Future<void> _storageWork = Future.value();
  Future<void>? _restoring;
  final Set<String> _watching = {};
  final Map<String, Completer<void>> _watchWakeups = {};
  final Set<String> _rechecks = {};

  /// A private socket event is only an invalidation hint, never proof that
  /// media is approved/visible. Wake the existing serialized watcher so it
  /// rechecks the authenticated decision AND canonical publication endpoint.
  void handleModerationUpdate(
    Map<String, dynamic> payload, {
    required String? currentUserId,
  }) {
    if (currentUserId == null ||
        currentUserId.isEmpty ||
        payload['userId'] != currentUserId) {
      return;
    }
    final itemId = payload['itemId'];
    final targetId = payload['targetId'];
    final targetType = payload['targetType'];
    if (itemId is! String ||
        itemId.isEmpty ||
        targetId is! String ||
        targetId.isEmpty ||
        targetType is! String) {
      return;
    }
    for (final item in List<PendingPublicMedia>.of(_items.values)) {
      if (item.targetType == targetType &&
          (item.usesExactReceipt ? item.id == itemId : item.id == targetId)) {
        _recheck(item);
        return;
      }
    }
    // The upload may have been made on another device or its local feedback
    // dismissed. Mounted screens still reload through authorized read APIs.
    switch (targetType) {
      case 'PERSONAL_STORY':
        StoryRepository.changes.value++;
      case 'CHECKIN_MEDIA':
        publicationChanges.value++;
      case 'VENUE_STORY':
        VenueStoryRepository.changes.value++;
      case 'VENUE_GALLERY':
        VenueGalleryRepository.changes.value++;
      case 'USER_PROFILE_PHOTO':
      case 'VENUE_COVER':
      case 'CHECKIN_AVATAR':
        avatarPublicationChanges.value++;
      case 'EVENT_PHOTO':
        eventPublicationChanges.value++;
    }
  }

  /// Catch up after foreground/reconnection without replaying any upload.
  void recheckPending() {
    for (final item in List<PendingPublicMedia>.of(_items.values)) {
      if (item.state == PendingPublicMediaState.underReview ||
          item.state == PendingPublicMediaState.checking ||
          item.state == PendingPublicMediaState.delayed ||
          item.state == PendingPublicMediaState.publishing ||
          item.state == PendingPublicMediaState.connectionIssue) {
        _recheck(item);
      }
    }
  }

  void _recheck(PendingPublicMedia item) {
    if (!item.hasServerReceipt ||
        _isRemovingUpload(item.id) ||
        item.state == PendingPublicMediaState.published ||
        item.state == PendingPublicMediaState.cancelled) {
      return;
    }
    final key = '$_session:${item.id}';
    if (_watching.contains(key)) {
      _rechecks.add(key);
      final wake = _watchWakeups[key];
      if (wake != null && !wake.isCompleted) wake.complete();
    } else {
      // An ERROR may subsequently be approved by an admin. Re-read, never
      // change to published from the event's payload or show a success popup.
      final pending = item.withState(PendingPublicMediaState.checking);
      _items[item.id] = pending;
      _startWatch(pending, _session, restored: true);
    }
  }

  Future<void> _waitForRecheck(String key, Duration duration) async {
    if (_rechecks.remove(key)) return;
    final wake = Completer<void>();
    _watchWakeups[key] = wake;
    try {
      await Future.any([_delay(duration), wake.future]);
    } finally {
      if (identical(_watchWakeups[key], wake)) _watchWakeups.remove(key);
      _rechecks.remove(key);
    }
  }

  /// Capture before preparing media so logout during compression invalidates it.
  int get sessionGeneration => _session;

  List<PendingPublicMedia> get items => List.unmodifiable(_items.values);

  bool isCurrentSession(int generation) => generation == _session;

  bool isEventPhotoTargetDeleted(PendingPublicMedia item) =>
      item.kind == PendingPublicMediaKind.eventPhoto &&
      (_deletedEventTargets.contains('${item.venueId}:event:${item.eventId}') ||
          _deletedEventTargets.contains(
            '${item.venueId}:series:${item.recurringRuleId}',
          ));

  MultipartUploadCancellation eventPhotoCancellation(String uploadId) =>
      _eventPhotoCancellations.putIfAbsent(
        uploadId,
        MultipartUploadCancellation.new,
      );

  /// Call only after the DELETE succeeds. A single occurrence never cancels a
  /// shared series upload still needed by the remaining occurrences.
  void confirmEventDeletion({
    required String venueId,
    required Set<String> removedEventIds,
    String? removedRecurringRuleId,
    required int expectedGeneration,
  }) {
    if (!isCurrentSession(expectedGeneration)) return;
    _deletedEventTargets.addAll(
      removedEventIds.map((id) => '$venueId:event:$id'),
    );
    if (removedRecurringRuleId != null) {
      _deletedEventTargets.add('$venueId:series:$removedRecurringRuleId');
    }
    final removed = _items.values.where(isEventPhotoTargetDeleted).toList();
    for (final item in removed) {
      eventPhotoCancellation(item.uploadId ?? item.id).cancel();
      _items.remove(item.id);
      _publishedIds.remove(item.id);
      if (item.uploadId != null) _publishedIds.remove(item.uploadId!);
    }
    _notify();
    unawaited(flushPersistence());
  }

  MultipartUploadCancellation storyCancellation(String uploadId) =>
      _storyCancellations.putIfAbsent(
        uploadId,
        MultipartUploadCancellation.new,
      );

  bool isCancellingStory(String id) {
    final item = byId(id);
    return _cancellingStories.contains(item?.uploadId ?? item?.id ?? id);
  }

  bool isRemovingEventPhoto(String id) =>
      _removingEventPhotos.contains(byId(id)?.id ?? id);

  bool _isRemovingUpload(String id) =>
      isCancellingStory(id) ||
      isRemovingEventPhoto(id) ||
      isRemovingGalleryPhoto(id);

  bool isRemovingGalleryPhoto(String id) =>
      _removingGalleryPhotos.contains(byId(id)?.id ?? id);

  /// A local Dismiss is not a cancellation: withdraw the exact server upload.
  /// Retain the captured item if approval removes it from the tracker meanwhile.
  Future<void> removeGalleryPhoto(
    PendingPublicMedia item, {
    required int expectedGeneration,
  }) async {
    if (!isCurrentSession(expectedGeneration)) return;
    if (item.kind != PendingPublicMediaKind.venueGallery ||
        !item.hasServerReceipt ||
        (item.venueId?.isEmpty ?? true)) {
      throw StateError('Upload removal could not be confirmed');
    }
    if (!_removingGalleryPhotos.add(item.id)) return;
    _notify();
    try {
      await _removeGalleryPhoto(
        item,
        () => isCurrentSession(expectedGeneration),
      );
      if (!isCurrentSession(expectedGeneration)) return;
      _items.remove(item.id);
      _publishedIds.remove(item.id);
      if (item.uploadId != null) _publishedIds.remove(item.uploadId!);
      _notify();
      VenueGalleryRepository.notifyChanged();
      // The server already confirmed withdrawal. Local disk work must not
      // leave an empty fullscreen viewer waiting; restored receipts revalidate.
      unawaited(flushPersistence());
    } finally {
      if (isCurrentSession(expectedGeneration)) {
        _removingGalleryPhotos.remove(item.id);
        _notify();
      }
    }
  }

  static Future<void> _defaultRemoveGalleryPhoto(
    PendingPublicMedia item,
    bool Function() isCurrentSession,
  ) => VenueGalleryRepository().deleteItem(
    item.venueId!,
    item.id,
    isCurrentSession: isCurrentSession,
  );

  Future<void> removeEventPhoto(
    String id, {
    required int expectedGeneration,
  }) async {
    if (!isCurrentSession(expectedGeneration)) return;
    final item = byId(id);
    if (item == null || item.kind != PendingPublicMediaKind.eventPhoto) return;
    if (!item.hasServerReceipt) {
      // Only a definite preparation/request failure is safe to dismiss locally.
      // An ambiguous transfer may still have succeeded on the server.
      if (item.state != PendingPublicMediaState.failed) {
        throw StateError('Upload removal could not be confirmed');
      }
      dismiss(item.id);
      return;
    }
    if (!_removingEventPhotos.add(item.id)) return;
    _notify();
    try {
      await _removeEventPhoto(item, () => isCurrentSession(expectedGeneration));
      if (!isCurrentSession(expectedGeneration)) return;
      _items.remove(item.id);
      _publishedIds.remove(item.id);
      if (item.uploadId != null) _publishedIds.remove(item.uploadId!);
      _notify();
      eventPublicationChanges.value++;
      await flushPersistence();
    } finally {
      if (isCurrentSession(expectedGeneration)) {
        _removingEventPhotos.remove(item.id);
        _notify();
      }
    }
  }

  static Future<void> _defaultRemoveEventPhoto(
    PendingPublicMedia item,
    bool Function() isCurrentSession,
  ) => ContentModerationRepository().removeEventPhotoUpload(
    venueId: item.venueId!,
    itemId: item.id,
    isCurrentSession: isCurrentSession,
  );

  Future<void> cancelStory(String id, {PendingPublicMedia? fallback}) async {
    final item = byId(id) ?? fallback;
    if (item == null || !item.isStory) return;
    final uploadId = item.uploadId ?? item.id;
    if (!_cancellingStories.add(uploadId)) return;
    final session = _session;
    _notify();
    try {
      await _cancelStory(item);
      if (session != _session) return;
      storyCancellation(uploadId).cancel();
      final current = byId(uploadId);
      if (current != null) _items.remove(current.id);
      if (current != null) _publishedIds.remove(current.id);
      _publishedIds.remove(item.id);
      _publishedIds.remove(uploadId);
      _notify();
      await flushPersistence();
    } finally {
      if (session == _session) {
        _cancellingStories.remove(uploadId);
        _notify();
      }
    }
  }

  static Future<void> _defaultCancelStory(PendingPublicMedia item) async {
    final uploadId = item.uploadId ?? item.id;
    if (uploadId.startsWith('upload-')) {
      await ContentModerationRepository().cancelStoryUpload(
        uploadId: uploadId,
        venueId: item.kind == PendingPublicMediaKind.venueStory
            ? item.venueId
            : null,
        checkinId: item.checkinId,
      );
    } else if (item.hasServerReceipt) {
      // Older versions did not send a cancellable upload ID.
      if (item.kind == PendingPublicMediaKind.venueStory) {
        await VenueStoryRepository().deleteStory(item.venueId!, item.id);
      } else {
        await StoryRepository().deleteStory(item.id);
      }
    } else {
      throw StateError('Upload cancellation could not be confirmed');
    }
  }

  Future<void> _serializeStorage(Future<void> Function() work) {
    final next = _storageWork.then((_) => work());
    _storageWork = next.catchError((Object error) {
      // Persistence must never turn a successful server upload into a retry.
      if (kDebugMode) debugPrint('[Uploads] Local persistence unavailable');
    });
    return _storageWork;
  }

  Future<void> flushPersistence() => _storageWork;

  static String? _ownerFromToken(String token) {
    return uploadTokenOwner(token);
  }

  /// Called only after authentication succeeds. JWT parsing here is solely for
  /// local cache partitioning; API authorization remains on the server.
  Future<void> restoreAuthenticatedSession(
    String token, {
    required int expectedGeneration,
  }) async {
    if (expectedGeneration != _session) return;
    final owner = _ownerFromToken(token);
    if (owner == null ||
        !sameUploadOwner(token, await SecureStorage.getAccessToken())) {
      return;
    }
    if (expectedGeneration != _session) return;
    await bindSession(
      ownerId: owner,
      environment: '${AppConfig.buildEnv}|${AppConfig.baseUrl}',
      expectedGeneration: expectedGeneration,
    );
  }

  @visibleForTesting
  Future<void> bindSession({
    required String ownerId,
    required String environment,
    required int expectedGeneration,
  }) async {
    if (expectedGeneration != _session) return;
    final scope = sha256
        .convert(utf8.encode(jsonEncode([environment, ownerId])))
        .toString();
    if (_scope == scope) {
      await _restoring;
      return;
    }
    if (_scope != null) {
      clear();
      // An upload from the prior account must not be adopted by the next one.
    }
    final generation = _session;
    _scope = scope;
    final restore = _serializeStorage(() async {
      final stored = await _store?.read();
      if (generation != _session || _scope != scope) return;
      if (stored?['version'] == 1 && stored?['scope'] == scope) {
        final rows = stored?['items'];
        if (rows is List) {
          for (final row in rows.take(100)) {
            if (row is! Map) continue;
            var item = PendingPublicMedia.fromJson(
              Map<String, dynamic>.from(row),
            );
            if (item == null ||
                ((item.usesExactReceipt ||
                        item.kind == PendingPublicMediaKind.checkinMoment) &&
                    item.state == PendingPublicMediaState.published) ||
                _now().difference(item.createdAt) > const Duration(days: 7)) {
              continue;
            }
            if (!item.hasServerReceipt &&
                item.state != PendingPublicMediaState.failed) {
              item = item.withState(
                PendingPublicMediaState.connectionIssue,
                reason:
                    'This upload was interrupted. Check your content before sharing it again.',
              );
            }
            _items.putIfAbsent(item.id, () => item!);
          }
        }
      }
      changes.value++;
    });
    _restoring = restore;
    await restore;
    if (generation != _session || _scope != scope) return;
    _restoring = null;
    _persist();
    for (final item in List<PendingPublicMedia>.of(_items.values)) {
      _startWatch(item, generation, restored: true);
    }
  }

  /// No automatic replay: without a server receipt a timeout may still mean
  /// the server accepted the upload. Re-posting would risk duplicate content.
  Future<T> runUpload<T>({
    required PendingPublicMedia draft,
    required String token,
    required Future<T> Function(MultipartUploadProgress progress) send,
    required String? Function(T result) receiptId,
    String? Function(T result)? receiptVenueId,
    MultipartUploadProgress? onProgress,
    int? expectedGeneration,
  }) async {
    final generation = expectedGeneration ?? _session;
    if (generation != _session) throw StateError('UPLOAD_SESSION_CHANGED');
    await restoreAuthenticatedSession(token, expectedGeneration: generation);
    if (generation != _session ||
        _scope == null ||
        !sameUploadOwner(token, await SecureStorage.getAccessToken())) {
      throw StateError('UPLOAD_SESSION_CHANGED');
    }
    if (generation != _session) throw StateError('UPLOAD_SESSION_CHANGED');
    return runTrackedUpload(
      draft: draft,
      send: send,
      receiptId: receiptId,
      receiptVenueId: receiptVenueId,
      onProgress: onProgress,
      expectedGeneration: generation,
    );
  }

  @visibleForTesting
  Future<T> runTrackedUpload<T>({
    required PendingPublicMedia draft,
    required Future<T> Function(MultipartUploadProgress progress) send,
    required String? Function(T result) receiptId,
    String? Function(T result)? receiptVenueId,
    MultipartUploadProgress? onProgress,
    required int expectedGeneration,
  }) async {
    if (expectedGeneration != _session) {
      throw StateError('UPLOAD_SESSION_CHANGED');
    }
    if (isEventPhotoTargetDeleted(draft)) {
      throw const PublicMediaUploadCancelled();
    }
    if (draft.hasServerReceipt) {
      throw ArgumentError('An upload draft cannot have a server receipt');
    }
    if (draft.isStory) storyCancellation(draft.id).throwIfCancelled();
    final prepared = _items[draft.id];
    if (prepared != null &&
        prepared.state != PendingPublicMediaState.preparing) {
      throw StateError('UPLOAD_ALREADY_RUNNING');
    }
    _items[draft.id] = (prepared ?? draft).withState(
      PendingPublicMediaState.uploading,
    );
    _notify();
    await flushPersistence();
    if (expectedGeneration != _session) {
      throw StateError('UPLOAD_SESSION_CHANGED');
    }
    if (draft.isStory) storyCancellation(draft.id).throwIfCancelled();
    if (isEventPhotoTargetDeleted(draft)) {
      throw const PublicMediaUploadCancelled();
    }
    if (prepared == null) unawaited(_retainPreview(draft, expectedGeneration));
    try {
      final result = await PerformanceDiagnostics.mediaTransfer(
        kind: draft.kind.name,
        video: draft.isVideo,
        operation: () => send((sent, total) {
          if (expectedGeneration != _session) return;
          final current = _items[draft.id];
          final progress = total > 0 ? (sent / total).clamp(0.0, 1.0) : null;
          if (current != null &&
              progress != null &&
              (current.progress == null ||
                  (progress - current.progress!).abs() >= .01)) {
            _items[draft.id] = current.withProgress(progress);
            changes
                .value++; // Do not write the manifest for every network chunk.
          }
          // UI progress is optional. Disposed widgets must not abort a transfer.
          try {
            onProgress?.call(sent, total);
          } catch (_) {
            if (kDebugMode) debugPrint('[Uploads] Progress observer detached');
          }
        }),
      );
      if (expectedGeneration != _session) return result;
      if (isEventPhotoTargetDeleted(draft)) {
        throw const PublicMediaUploadCancelled();
      }
      if (draft.isStory && storyCancellation(draft.id).isCancelled) {
        throw const PublicMediaUploadCancelled();
      }
      final id = receiptId(result);
      if (id == null || id.isEmpty) throw StateError('UPLOAD_RECEIPT_MISSING');
      final current = _items.remove(draft.id) ?? draft;
      track(
        current.withReceipt(id, resolvedVenueId: receiptVenueId?.call(result)),
      );
      await flushPersistence();
      return result;
    } catch (error) {
      if (expectedGeneration == _session && isAwsSharingPermissionError(error)) {
        // No upload was accepted. A privacy choice is not a network failure or
        // a moderation rejection, and must not leave a stuck "Sharing" card.
        _items.remove(draft.id);
        _notify();
        await flushPersistence();
        rethrow;
      }
      if (expectedGeneration == _session &&
          !(draft.isStory && storyCancellation(draft.id).isCancelled) &&
          _items.containsKey(draft.id)) {
        _items[draft.id] = _items[draft.id]!.withState(
          error is PublicMediaUploadRejected
              ? PendingPublicMediaState.failed
              : PendingPublicMediaState.connectionIssue,
          reason: error is PublicMediaUploadRejected
              ? 'Your upload was not accepted. Please try again.'
              : 'We could not confirm this upload. Check your content before sharing it again.',
        );
        _notify();
        await flushPersistence();
      }
      rethrow;
    }
  }

  static String newUploadId() =>
      'upload-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  /// Register the owner preview before compression starts or the camera route
  /// closes. The matching repository adopts this exact job when sending.
  void prepareUpload(
    PendingPublicMedia draft, {
    required int expectedGeneration,
  }) {
    if (expectedGeneration != _session ||
        draft.hasServerReceipt ||
        isEventPhotoTargetDeleted(draft)) {
      return;
    }
    track(draft.withState(PendingPublicMediaState.preparing));
  }

  void failPreparedUpload(
    String id, {
    required int expectedGeneration,
    required String message,
  }) {
    if (expectedGeneration != _session) return;
    final current = byId(id);
    if (current == null ||
        current.hasServerReceipt ||
        (current.state != PendingPublicMediaState.preparing &&
            current.state != PendingPublicMediaState.failed)) {
      return;
    }
    _items[current.id] = current.withState(
      PendingPublicMediaState.failed,
      reason: message,
    );
    _notify();
  }

  /// Preparation may finish after the originating screen has been dismissed.
  /// Keep its failure visible through the same owner-only upload list.
  void recordPreparationFailure({
    required int expectedGeneration,
    required PendingPublicMediaKind kind,
    required String message,
    String? venueId,
    String? checkinId,
    bool isVideo = false,
  }) {
    if (expectedGeneration != _session || _scope == null) return;
    track(
      PendingPublicMedia(
        id: newUploadId(),
        kind: kind,
        venueId: venueId,
        checkinId: checkinId,
        localPath: '',
        isVideo: isVideo,
        createdAt: _now(),
        hasServerReceipt: false,
        state: PendingPublicMediaState.failed,
        message: message,
      ),
    );
  }

  Future<void> _retainPreview(PendingPublicMedia item, int generation) async {
    String? path;
    try {
      path = item.isVideo
          ? await VideoThumbnail.thumbnailFile(
              video: item.localPath,
              imageFormat: ImageFormat.JPEG,
              maxWidth: 540,
              quality: 65,
            )
          : item.localPath;
    } catch (_) {
      return;
    }
    if (path == null || path.isEmpty) return;
    await retainPreparedPreview(item.id, path, expectedGeneration: generation);
  }

  /// Replace a picker source (e.g. HEIC) with its displayable JPEG, or retain
  /// the generated video thumbnail independently of temporary encoder files.
  Future<void> retainPreparedPreview(
    String id,
    String path, {
    required int expectedGeneration,
  }) => _serializeStorage(() async {
    if (expectedGeneration != _session) return;
    var current = byId(id);
    if (current == null ||
        current.state == PendingPublicMediaState.rejected ||
        current.state == PendingPublicMediaState.failed ||
        current.state == PendingPublicMediaState.cancelled) {
      return;
    }
    final retained = await _store?.retainPreview(id, path) ?? path;
    if (expectedGeneration != _session) return;
    current = byId(id);
    if (current == null ||
        current.state == PendingPublicMediaState.rejected ||
        current.state == PendingPublicMediaState.failed ||
        current.state == PendingPublicMediaState.cancelled) {
      return;
    }
    _items[current.id] = current.withPreview(retained);
    _notify();
  });

  void _persist() {
    final scope = _scope;
    if (_store == null || scope == null) return;
    final generation = _session;
    final snapshot = List<PendingPublicMedia>.of(_items.values);
    final value = {
      'version': 1,
      'scope': scope,
      'items': snapshot.map((i) => i.toJson()).toList(),
    };
    unawaited(
      _serializeStorage(() async {
        if (generation != _session || scope != _scope) return;
        await _store.write(value);
        // Preview preparation can finish while earlier manifest writes wait.
        // Protect every currently referenced file, including that newer preview.
        final previews = _items.values
            .where(
              (item) =>
                  item.state != PendingPublicMediaState.rejected &&
                  item.state != PendingPublicMediaState.failed &&
                  item.state != PendingPublicMediaState.cancelled,
            )
            .map((item) => item.previewPath)
            .whereType<String>()
            .toSet();
        await _store.prunePreviews(previews);
      }),
    );
  }

  List<PendingPublicMedia> forKind(
    PendingPublicMediaKind kind, {
    String? venueId,
  }) {
    final matches = _items.values
        .where(
          (item) =>
              item.kind == kind && (venueId == null || item.venueId == venueId),
        )
        .toList();
    matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches;
  }

  PendingPublicMedia? latest(PendingPublicMediaKind kind, {String? venueId}) {
    final matches = forKind(kind, venueId: venueId);
    return matches.isEmpty ? null : matches.first;
  }

  PendingPublicMedia? byId(String id) {
    final direct = _items[id];
    if (direct != null) return direct;
    for (final item in _items.values) {
      if (item.uploadId == id) return item;
    }
    return null;
  }

  bool wasPublished(String id) => _publishedIds.contains(id);

  void track(PendingPublicMedia item) {
    if (item.id.isEmpty ||
        _items.containsKey(item.id) ||
        isEventPhotoTargetDeleted(item)) {
      return;
    }
    _publishedIds.remove(item.id);
    // Each upload owns its outcome. Sharing another Moment must not erase an
    // earlier rejection/failure before the owner has seen its explanation.
    _items[item.id] = item;
    _notify();
    if (item.previewPath == null &&
        item.uploadId == null &&
        item.state != PendingPublicMediaState.failed &&
        item.state != PendingPublicMediaState.rejected) {
      unawaited(_retainPreview(item, _session));
    }
    _startWatch(item, _session);
  }

  void _startWatch(
    PendingPublicMedia item,
    int session, {
    bool restored = false,
  }) {
    if (!item.hasServerReceipt ||
        item.state == PendingPublicMediaState.rejected ||
        item.state == PendingPublicMediaState.failed ||
        (item.state == PendingPublicMediaState.cancelled &&
            !(restored && item.isAccountAvatar)) ||
        item.state == PendingPublicMediaState.published) {
      return;
    }
    final key = '$session:${item.id}';
    if (!_watching.add(key)) return;
    unawaited(
      _watch(
        item,
        session,
        startedAt: restored ? item.createdAt : _now(),
      ).whenComplete(() {
        _watching.remove(key);
        _watchWakeups.remove(key);
        _rechecks.remove(key);
      }),
    );
  }

  void dismiss(String id) {
    final current = byId(id);
    if (current == null ||
        current.state == PendingPublicMediaState.uploading ||
        current.state == PendingPublicMediaState.preparing) {
      return;
    }
    if (_items.remove(current.id) != null) _notify();
  }

  /// Remove already-viewed not-shared feedback from the local Story bubble only.
  /// The server decision/history is unchanged; active uploads and other media
  /// must never be removed by leaving a Story viewer.
  void acknowledgeStoryFeedback(String id, {required int expectedGeneration}) {
    if (!isCurrentSession(expectedGeneration)) return;
    final current = byId(id);
    if (current == null ||
        !current.isStory ||
        (current.state != PendingPublicMediaState.rejected &&
            current.state != PendingPublicMediaState.failed)) {
      return;
    }
    _items.remove(current.id);
    _notify();
  }

  void clear() {
    _session++;
    for (final wake in _watchWakeups.values) {
      if (!wake.isCompleted) wake.complete();
    }
    _watchWakeups.clear();
    _rechecks.clear();
    _scope = null;
    _restoring = null;
    _items.clear();
    _publishedIds.clear();
    _publishedRequests.clear();
    _watching.clear();
    _cancellingStories.clear();
    _removingEventPhotos.clear();
    _removingGalleryPhotos.clear();
    _storyCancellations.clear();
    _eventPhotoCancellations.clear();
    _deletedEventTargets.clear();
    unawaited(_serializeStorage(() async => _store?.clear()));
    _notify();
  }

  void _notify() {
    if (PerformanceDiagnostics.enabled) {
      final transfers = _items.values
          .where(
            (item) =>
                item.state == PendingPublicMediaState.preparing ||
                item.state == PendingPublicMediaState.uploading,
          )
          .toList();
      PerformanceDiagnostics.setUploadCounts(
        transfers: transfers.length,
        videos: transfers.where((item) => item.isVideo).length,
        pending: _items.values
            .where(
              (item) =>
                  item.state == PendingPublicMediaState.checking ||
                  item.state == PendingPublicMediaState.publishing ||
                  item.state == PendingPublicMediaState.delayed ||
                  item.state == PendingPublicMediaState.underReview,
            )
            .length,
      );
    }
    changes.value++;
    _persist();
  }

  Future<void> _watch(
    PendingPublicMedia item,
    int session, {
    required DateTime startedAt,
  }) async {
    var lastDecision = const MediaModerationSnapshot();
    var previousSupersededRead = false;
    final watchKey = '$session:${item.id}';
    while (session == _session && _items.containsKey(item.id)) {
      if (_isRemovingUpload(item.id)) {
        await _delay(const Duration(seconds: 2));
        continue;
      }
      var isPublished = false;
      var publicReadFailed = false;
      var moderationReadFailed = false;
      var hasFreshDecision = false;
      try {
        // Read the small owner-only decision first. While AWS is working, do
        // not repeatedly fetch/sign an entire profile, story feed or gallery.
        final decision = await _moderationLookup(item);
        if (session != _session || !_items.containsKey(item.id)) return;
        if (_isRemovingUpload(item.id)) continue;
        if (decision.status != null) {
          lastDecision = decision;
          hasFreshDecision = true;
        }
      } catch (_) {
        moderationReadFailed = true;
      }
      if (session != _session || !_items.containsKey(item.id)) return;
      try {
        // The public endpoint is the authority for visibility. An APPROVED
        // moderation row may precede signed URL/publication propagation.
        if (lastDecision.publicationDisabled) {
          // A historical approval is not permission to publish while the
          // feature is paused. Do not poll the public feed indefinitely.
          isPublished = false;
        } else if (item.usesExactReceipt) {
          // Avatar target IDs are reused. Follow the exact moderation receipt,
          // never an older APPROVED row for the same user/venue.
          isPublished =
              lastDecision.status == 'APPROVED' &&
              lastDecision.photoPublication == 'PUBLISHED';
        } else if (lastDecision.status == 'APPROVED' ||
            lastDecision.status == null) {
          // Retain the public visibility confirmation, including compatibility
          // with older APIs. A local approval never publishes private media.
          isPublished = await _publishedLookup(item);
        }
      } catch (_) {
        publicReadFailed = true;
        // A failed public read must not prevent reading the moderation result.
      }
      if (session != _session || !_items.containsKey(item.id)) return;
      if (_isRemovingUpload(item.id)) continue;
      // A decision changed while either HTTP read was in flight. Discard the
      // old result and re-read serially rather than publishing a stale result.
      if (_rechecks.remove(watchKey)) continue;
      if (isPublished) {
        if (session != _session) return;
        _publishedIds.add(item.id);
        if (item.uploadId != null) _publishedIds.add(item.uploadId!);
        while (_publishedIds.length > 100) {
          _publishedIds.remove(_publishedIds.first);
        }
        if (item.usesExactReceipt ||
            item.kind == PendingPublicMediaKind.checkinMoment) {
          // Short, bounded handover while mounted screens reload the canonical
          // media. Keep the approved preview until the quiet fetch completes.
          _items[item.id] = _items[item.id]!.withState(
            PendingPublicMediaState.published,
          );
          _notify();
          if (item.isAvatar) {
            avatarPublicationChanges.value++;
          } else if (item.kind == PendingPublicMediaKind.eventPhoto) {
            eventPublicationChanges.value++;
          } else {
            publicationChanges.value++;
          }
          await _delay(const Duration(seconds: 10));
          if (session == _session &&
              _items[item.id]?.state == PendingPublicMediaState.published) {
            dismiss(item.id);
          }
          return;
        }
        dismiss(item.id);
        switch (item.kind) {
          case PendingPublicMediaKind.checkinMoment:
            publicationChanges.value++;
          case PendingPublicMediaKind.personalStory:
            StoryRepository.changes.value++;
          case PendingPublicMediaKind.venueStory:
            VenueStoryRepository.changes.value++;
          case PendingPublicMediaKind.venueGallery:
            VenueGalleryRepository.changes.value++;
          case PendingPublicMediaKind.personalAvatar:
          case PendingPublicMediaKind.venueAvatar:
          case PendingPublicMediaKind.checkinAvatar:
          case PendingPublicMediaKind.eventPhoto:
            break;
        }
        return;
      }
      final supersededSignal =
          item.usesExactReceipt &&
          lastDecision.photoPublication == 'SUPERSEDED' &&
          lastDecision.status != 'REJECTED' &&
          lastDecision.status != 'ERROR';
      // A replaced avatar may be observed during an approval handover on an
      // older API. Require two consecutive fresh confirmations before ending
      // its watch. Network failures must not confirm a cached obsolete result.
      final superseded =
          supersededSignal &&
          (!item.isAccountAvatar ||
              (previousSupersededRead && hasFreshDecision));
      previousSupersededRead = supersededSignal && hasFreshDecision;
      if (superseded && item.isAccountAvatar) {
        // A removed/replaced candidate needs no lingering error badge. Refresh
        // the canonical photo, never publish this obsolete preview or replay it.
        dismiss(item.id);
        avatarPublicationChanges.value++;
        return;
      }
      final next = superseded
          ? PendingPublicMediaState.cancelled
          : resolvePublicMediaState(
              moderation: lastDecision,
              elapsed: _now().difference(startedAt),
              isVideo: item.isVideo,
              connectionIssue:
                  moderationReadFailed ||
                  (publicReadFailed &&
                      (item.usesExactReceipt ||
                          (lastDecision.status == null ||
                              lastDecision.status == 'APPROVED'))),
            );
      final current = _items[item.id]!;
      if (current.state != next || current.message != lastDecision.message) {
        _items[item.id] = current.withState(
          next,
          reason: superseded
              ? (item.isAvatar
                    ? 'A newer photo was selected or this photo was removed.'
                    : 'This event photo was removed or the event is no longer available.')
              : lastDecision.message,
        );
        _notify();
      }
      if (next == PendingPublicMediaState.rejected ||
          next == PendingPublicMediaState.failed ||
          next == PendingPublicMediaState.cancelled) {
        if (item.kind == PendingPublicMediaKind.checkinAvatar) {
          // The backend may have cleared a rejected/superseded crop. Refresh
          // canonical avatars as well as removing the private owner preview.
          avatarPublicationChanges.value++;
        }
        return;
      }
      await _waitForRecheck(
        watchKey,
        publicMediaPollDelay(
          isVideo: item.isVideo,
          elapsed: _now().difference(startedAt),
          state: next,
          activeUploads: _watching.length,
        ),
      );
    }
  }

  static final Map<String, Future<Set<String>>> _publishedRequests = {};

  static Future<bool> _defaultPublishedLookup(PendingPublicMedia item) async {
    final key = '${item.kind.name}:${item.checkinId ?? item.venueId ?? 'me'}';
    final request = _publishedRequests[key] ??= _loadPublishedIds(item);
    try {
      return (await request).contains(item.id);
    } finally {
      if (identical(_publishedRequests[key], request)) {
        _publishedRequests.remove(key);
      }
    }
  }

  static Future<Set<String>> _loadPublishedIds(PendingPublicMedia item) async {
    switch (item.kind) {
      case PendingPublicMediaKind.personalAvatar:
      case PendingPublicMediaKind.venueAvatar:
      case PendingPublicMediaKind.checkinAvatar:
      case PendingPublicMediaKind.eventPhoto:
        return {}; // Avatar publication comes from its exact review receipt.
      case PendingPublicMediaKind.checkinMoment:
        final checkinId = item.checkinId;
        if (checkinId == null) return {};
        return (await CheckinRepository().getCheckinProfile(
          checkinId,
        )).media.map((media) => media.id).toSet();
      case PendingPublicMediaKind.personalStory:
        return (await StoryRepository().getMyStories())
            .map((s) => s.id)
            .toSet();
      case PendingPublicMediaKind.venueStory:
        final venueId = item.venueId;
        if (venueId == null) return {};
        return (await VenueStoryRepository().getVenueStories(
          venueId,
        )).map((s) => s.id).toSet();
      case PendingPublicMediaKind.venueGallery:
        final venueId = item.venueId;
        if (venueId == null) return {};
        return (await VenueGalleryRepository().getGallery(
          venueId,
        )).map((s) => s.id).toSet();
    }
  }

  static Future<MediaModerationSnapshot> _defaultModerationLookup(
    PendingPublicMedia item,
  ) async {
    final repository = ContentModerationRepository();
    if (item.usesExactReceipt) {
      final result = await repository.listMyItems(itemId: item.id, limit: 1);
      for (final row in result.items) {
        if (row.id == item.id && row.targetType == item.targetType) {
          return row.moderationSnapshot;
        }
      }
      return const MediaModerationSnapshot();
    }
    final result = await repository.listMyItems(
      limit: 1,
      targetType: item.targetType,
      targetId: item.id,
    );
    for (final row in result.items) {
      if (row.targetType == item.targetType && row.targetId == item.id) {
        return row.moderationSnapshot;
      }
    }
    // Older deployed APIs ignore the two new query fields. During rollout,
    // search the recent owner-only pages so the preview still resolves.
    if (result.total > result.items.length) {
      for (var page = 1; page <= 5; page++) {
        final fallback = await repository.listMyItems(page: page, limit: 50);
        for (final row in fallback.items) {
          if (row.targetType == item.targetType && row.targetId == item.id) {
            return row.moderationSnapshot;
          }
        }
        if (page * 50 >= fallback.total) break;
      }
    }
    return const MediaModerationSnapshot();
  }
}
