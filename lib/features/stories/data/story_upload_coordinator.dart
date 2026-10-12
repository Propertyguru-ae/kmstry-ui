import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';
import 'story_repository.dart';
import 'story_upload_failure.dart';

typedef StoryUploadSender =
    Future<void> Function(
      PendingPublicMedia draft,
      File file,
      int session,
      String? textOverlayJson,
    );

/// Camera screens enqueue a story and return immediately. This coordinator
/// owns preparation, sending and failure handling without retaining a widget.
class StoryUploadCoordinator {
  StoryUploadCoordinator._({
    PendingPublicMediaService? service,
    Future<File> Function(File)? prepareVideo,
    StoryUploadSender? sender,
  }) : _service = service ?? PendingPublicMediaService.instance,
       _prepareVideo = prepareVideo ?? MediaCompressor.compressVenueVideo,
       _sender = sender ?? _send;

  static final instance = StoryUploadCoordinator._();

  @visibleForTesting
  StoryUploadCoordinator.forTest({
    required PendingPublicMediaService service,
    required Future<File> Function(File) prepareVideo,
    required StoryUploadSender sender,
  }) : this._(service: service, prepareVideo: prepareVideo, sender: sender);

  final PendingPublicMediaService _service;
  final Future<File> Function(File) _prepareVideo;
  final StoryUploadSender _sender;

  ({String id, Future<void> completed}) sharePersonal({
    required File file,
    required String checkinId,
    String? venueId,
    String? textOverlayJson,
  }) => _enqueue(
    file: file,
    kind: PendingPublicMediaKind.personalStory,
    checkinId: checkinId,
    venueId: venueId,
    textOverlayJson: textOverlayJson,
  );

  ({String id, Future<void> completed}) shareVenue({
    required File file,
    required String venueId,
    String? textOverlayJson,
  }) => _enqueue(
    file: file,
    kind: PendingPublicMediaKind.venueStory,
    venueId: venueId,
    textOverlayJson: textOverlayJson,
  );

  ({String id, Future<void> completed}) _enqueue({
    required File file,
    required PendingPublicMediaKind kind,
    String? checkinId,
    String? venueId,
    String? textOverlayJson,
  }) {
    final session = _service.sessionGeneration;
    final draft = PendingPublicMedia(
      id: PendingPublicMediaService.newUploadId(),
      kind: kind,
      venueId: venueId,
      checkinId: checkinId,
      localPath: file.path,
      isVideo: RegExp(
        r'\.(mp4|mov|avi|m4v)$',
        caseSensitive: false,
      ).hasMatch(file.path),
      createdAt: DateTime.now(),
      hasServerReceipt: false,
      textOverlay: MediaTextOverlay.fromJson(textOverlayJson),
    );
    _service.prepareUpload(draft, expectedGeneration: session);
    return (
      id: draft.id,
      completed: _complete(draft, file, session, textOverlayJson),
    );
  }

  Future<void> _complete(
    PendingPublicMedia draft,
    File original,
    int session,
    String? overlay,
  ) async {
    var stage = 'preparing_media';
    final releaseVideo = draft.isVideo
        ? MediaCompressor.retainVideoFiles()
        : null;
    try {
      final prepared = draft.isVideo ? await _prepareVideo(original) : original;
      if (!_service.isCurrentSession(session)) return;
      if (draft.isVideo && await prepared.length() > 50 * 1024 * 1024) {
        throw const PublicMediaUploadRejected('VIDEO_TOO_LARGE');
      }
      if (!_service.isCurrentSession(session)) return;
      stage = 'sending';
      if (kDebugMode) {
        debugPrint(
          '[StoryUpload] ${jsonEncode({'event': 'sending', 'uploadId': draft.id, 'kind': draft.kind.name, 'isVideo': draft.isVideo})}',
        );
      }
      await _sender(draft, prepared, session, overlay);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[StoryUpload] ${jsonEncode({
            'event': 'failed',
            'uploadId': draft.id,
            'stage': stage,
            'kind': draft.kind.name,
            'isVideo': draft.isVideo,
            'errorType': error.runtimeType.toString(),
            if (error is StoryUploadFailure) ...{'code': error.code, 'status': error.statusCode},
            if (error is StateError && const {'UPLOAD_SESSION_CHANGED', 'UPLOAD_ALREADY_RUNNING', 'UPLOAD_RECEIPT_MISSING'}.contains(error.message)) 'code': error.message,
            if (error is PublicMediaUploadRejected && error.description == 'VIDEO_TOO_LARGE') 'code': error.description,
          })}',
        );
      }
      // The transfer manager already retains uncertain network outcomes. Only
      // definite/preparation failures can be replaced with this safe copy.
      _service.failPreparedUpload(
        draft.id,
        expectedGeneration: session,
        message: _failureMessage(error),
      );
    } finally {
      releaseVideo?.call();
    }
  }

  static String _failureMessage(Object error) {
    if (error is StoryUploadFailure) return error.message;
    final text = error.toString();
    if (text.contains('ANONYMOUS_STORY_BLOCKED')) {
      return 'Turn off Anonymous Mode to share a story.';
    }
    if (text.contains('PLAN_UPGRADE_REQUIRED')) {
      return 'Your venue needs the Social plan to share stories.';
    }
    if (text.contains('60 seconds or shorter')) {
      return 'Choose a video that is 60 seconds or shorter.';
    }
    if (text.contains('VIDEO_TOO_LARGE') || text.contains('(413)')) {
      return 'This video is too large. Please choose a smaller file.';
    }
    return 'Your story could not be shared. Please try another file.';
  }

  static Future<void> _send(
    PendingPublicMedia draft,
    File file,
    int session,
    String? overlay,
  ) async {
    if (draft.kind == PendingPublicMediaKind.personalStory) {
      await StoryRepository().createStory(
        checkinId: draft.checkinId!,
        file: file,
        mediaType: draft.isVideo ? 'video' : 'photo',
        textOverlayJson: overlay,
        uploadSession: session,
        pendingDraft: draft,
      );
    } else {
      await VenueStoryRepository().createVenueStory(
        venueId: draft.venueId!,
        file: file,
        mediaType: draft.isVideo ? 'video' : 'photo',
        textOverlayJson: overlay,
        uploadSession: session,
        pendingDraft: draft,
      );
    }
  }
}
