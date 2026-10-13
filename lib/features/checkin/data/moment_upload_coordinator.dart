import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'checkin_repository.dart';
import 'moment_upload_failure.dart';

typedef MomentSender =
    Future<void> Function(
      PendingPublicMedia draft,
      File file,
      int session,
      String? overlay,
    );

/// Transfers belong to the signed-in session, not the profile/camera route.
/// Approval remains entirely server-side; a local preview never activates a check-in.
class MomentUploadCoordinator {
  MomentUploadCoordinator._({
    PendingPublicMediaService? service,
    Future<File> Function(File)? prepareVideo,
    Future<Duration> Function(File)? videoDuration,
    Future<String?> Function(File)? thumbnail,
    MomentSender? sender,
  }) : _service = service ?? PendingPublicMediaService.instance,
       _prepareVideo = prepareVideo ?? MediaCompressor.compressVenueVideo,
       _videoDuration = videoDuration ?? _duration,
       _thumbnail = thumbnail ?? _videoThumbnail,
       _sender = sender ?? _send;
  static final instance = MomentUploadCoordinator._();
  @visibleForTesting
  MomentUploadCoordinator.forTest({
    required PendingPublicMediaService service,
    required Future<File> Function(File) prepareVideo,
    required Future<Duration> Function(File) videoDuration,
    required Future<String?> Function(File) thumbnail,
    required MomentSender sender,
  }) : this._(
         service: service,
         prepareVideo: prepareVideo,
         videoDuration: videoDuration,
         thumbnail: thumbnail,
         sender: sender,
       );
  final PendingPublicMediaService _service;
  final Future<File> Function(File) _prepareVideo;
  final Future<Duration> Function(File) _videoDuration;
  final Future<String?> Function(File) _thumbnail;
  final MomentSender _sender;
  final Queue<_MomentJob> _queue = Queue();
  int _active = 0;

  ({String id, Future<void> completed})? share({
    required File file,
    required String checkinId,
    String? venueId,
    String? textOverlayJson,
    String? previewPath,
    required int expectedGeneration,
  }) {
    if (!_service.isCurrentSession(expectedGeneration)) return null;
    if (checkinId.trim().isEmpty) throw ArgumentError('Check-in required');
    final duplicate = _service
        .forKind(PendingPublicMediaKind.checkinMoment)
        .any(
          (i) =>
              i.checkinId == checkinId &&
              i.localPath == file.path &&
              i.state != PendingPublicMediaState.rejected &&
              i.state != PendingPublicMediaState.failed &&
              i.state != PendingPublicMediaState.cancelled,
        );
    if (duplicate) return null;
    final draft = PendingPublicMedia(
      id: PendingPublicMediaService.newUploadId(),
      kind: PendingPublicMediaKind.checkinMoment,
      checkinId: checkinId,
      venueId: venueId,
      localPath: file.path,
      isVideo: RegExp(
        r'\.(mp4|mov|m4v|webm|avi)$',
        caseSensitive: false,
      ).hasMatch(file.path),
      createdAt: DateTime.now(),
      hasServerReceipt: false,
    );
    _service.prepareUpload(draft, expectedGeneration: expectedGeneration);
    // Retain from enqueue time: a queued video must survive another upload's cleanup.
    final job = _MomentJob(
      draft,
      file,
      expectedGeneration,
      textOverlayJson,
      draft.isVideo ? MediaCompressor.retainVideoFiles() : null,
    );
    if (previewPath != null) {
      unawaited(
        _service.retainPreparedPreview(
          draft.id,
          previewPath,
          expectedGeneration: expectedGeneration,
        ),
      );
    }
    _queue.add(job);
    _drain();
    return (id: draft.id, completed: job.completed.future);
  }

  void _drain() {
    while (_active < 2 && _queue.isNotEmpty) {
      _active++;
      unawaited(_run(_queue.removeFirst()));
    }
  }

  Future<void> _run(_MomentJob job) async {
    var stage = 'starting';
    try {
      if (!_service.isCurrentSession(job.session)) return;
      if (job.draft.isVideo) {
        stage = 'reading_video';
        final duration = await _videoDuration(job.file);
        if (duration <= Duration.zero) {
          throw const PublicMediaUploadRejected('VIDEO_UNREADABLE');
        }
        if (duration > const Duration(seconds: 60)) {
          throw const PublicMediaUploadRejected('VIDEO_DURATION');
        }
      }
      if (!_service.isCurrentSession(job.session)) return;
      stage = 'preparing_media';
      final prepared = job.draft.isVideo
          ? await _prepareVideo(job.file)
          : job.file;
      if (!_service.isCurrentSession(job.session)) return;
      if (job.draft.isVideo && await prepared.length() > 50 * 1024 * 1024) {
        throw const PublicMediaUploadRejected('VIDEO_TOO_LARGE');
      }
      String? preview = job.draft.isVideo ? null : prepared.path;
      if (job.draft.isVideo) {
        try {
          preview = await _thumbnail(prepared);
        } catch (_) {}
      }
      if (preview != null) {
        stage = 'retaining_preview';
        await _service.retainPreparedPreview(
          job.draft.id,
          preview,
          expectedGeneration: job.session,
        );
      }
      if (!_service.isCurrentSession(job.session)) return;
      stage = 'sending';
      if (kDebugMode) {
        debugPrint(
          '[MomentUpload] ${jsonEncode({'event': 'sending', 'uploadId': job.draft.id, 'isVideo': job.draft.isVideo})}',
        );
      }
      await _sender(job.draft, prepared, job.session, job.overlay);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[MomentUpload] ${jsonEncode({
            'event': 'failed',
            'uploadId': job.draft.id,
            'stage': stage,
            'isVideo': job.draft.isVideo,
            'errorType': error.runtimeType.toString(),
            if (error is StateError && const {'UPLOAD_SESSION_CHANGED', 'UPLOAD_ALREADY_RUNNING', 'UPLOAD_RECEIPT_MISSING'}.contains(error.message)) 'code': error.message,
            if (error is PublicMediaUploadRejected && const {'VIDEO_DURATION', 'VIDEO_UNREADABLE', 'VIDEO_TOO_LARGE'}.contains(error.description)) 'code': error.description,
            if (error is MomentUploadFailure) ...{'code': error.code, 'status': error.statusCode},
          })}',
        );
      }
      final text = error.toString();
      _service.failPreparedUpload(
        job.draft.id,
        expectedGeneration: job.session,
        message: error is MomentUploadFailure
            ? error.message
            : text.contains('VIDEO_DURATION')
            ? 'Choose a video that is 60 seconds or shorter.'
            : text.contains('VIDEO_TOO_LARGE') || text.contains('(413)')
            ? 'This video is too large. Please choose a smaller file.'
            : stage == 'reading_video'
            ? 'This video could not be read. Please record a new video and try again.'
            : 'This Moment could not be uploaded. Please try again or choose another file.',
      );
    } finally {
      job.releaseVideo?.call();
      job.completed.complete();
      _active--;
      _drain();
    }
  }

  static Future<Duration> _duration(File file) async {
    final player = VideoPlayerController.file(file);
    try {
      await player.initialize().timeout(const Duration(seconds: 15));
      return player.value.duration;
    } finally {
      await player.dispose();
    }
  }

  static Future<String?> _videoThumbnail(File file) =>
      VideoThumbnail.thumbnailFile(
        video: file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 540,
        quality: 80,
      );
  static Future<void> _send(
    PendingPublicMedia draft,
    File file,
    int session,
    String? overlay,
  ) async {
    await CheckinRepository().uploadCheckinMedia(
      checkinId: draft.checkinId!,
      file: file,
      isFeatured: false,
      trackInBackground: true,
      venueId: draft.venueId,
      uploadSession: session,
      pendingDraft: draft,
      textOverlayJson: overlay,
    );
  }
}

class _MomentJob {
  _MomentJob(
    this.draft,
    this.file,
    this.session,
    this.overlay,
    this.releaseVideo,
  );
  final PendingPublicMedia draft;
  final File file;
  final int session;
  final String? overlay;
  final void Function()? releaseVideo;
  final completed = Completer<void>();
}
