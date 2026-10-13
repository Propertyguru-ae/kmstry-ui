import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'venue_gallery_repository.dart';

typedef GalleryUploadSender =
    Future<void> Function(
      PendingPublicMedia draft,
      File file,
      File? thumbnail,
      int session,
    );

/// Home and profile enqueue the same owner-only jobs. Preparation and transfer
/// do not hold a BuildContext or depend on the originating route staying open.
class VenueGalleryUploadCoordinator {
  VenueGalleryUploadCoordinator._({
    PendingPublicMediaService? service,
    Future<File> Function(File)? prepareImage,
    Future<File> Function(File)? prepareVideo,
    Future<Duration> Function(File)? videoDuration,
    Future<File?> Function(File)? thumbnail,
    GalleryUploadSender? sender,
  }) : _service = service ?? PendingPublicMediaService.instance,
       _prepareImage = prepareImage ?? MediaCompressor.compressImage,
       _prepareVideo = prepareVideo ?? MediaCompressor.compressGalleryVideo,
       _videoDuration = videoDuration ?? _readDuration,
       _thumbnail = thumbnail ?? _makeThumbnail,
       _sender = sender ?? _send;

  static final instance = VenueGalleryUploadCoordinator._();

  @visibleForTesting
  VenueGalleryUploadCoordinator.forTest({
    required PendingPublicMediaService service,
    required Future<File> Function(File) prepareImage,
    required Future<File> Function(File) prepareVideo,
    required Future<Duration> Function(File) videoDuration,
    required Future<File?> Function(File) thumbnail,
    required GalleryUploadSender sender,
  }) : this._(
         service: service,
         prepareImage: prepareImage,
         prepareVideo: prepareVideo,
         videoDuration: videoDuration,
         thumbnail: thumbnail,
         sender: sender,
       );

  final PendingPublicMediaService _service;
  final Future<File> Function(File) _prepareImage;
  final Future<File> Function(File) _prepareVideo;
  final Future<Duration> Function(File) _videoDuration;
  final Future<File?> Function(File) _thumbnail;
  final GalleryUploadSender _sender;
  final Queue<_GalleryUploadJob> _queue = Queue();
  int _active = 0;

  static const _videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    '3gp',
    'webm',
    'mkv',
    'avi',
    'mpeg',
    'mpg',
  };
  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'gif',
    'bmp',
  };
  static bool isVideoPath(String path) =>
      _videoExtensions.contains(path.split('.').last.toLowerCase());
  static bool isMediaPath(String path) {
    final extension = path.split('.').last.toLowerCase();
    return _videoExtensions.contains(extension) ||
        _imageExtensions.contains(extension);
  }

  ({List<String> ids, Future<void> completed}) share({
    required String venueId,
    required List<File> files,
    int? expectedGeneration,
  }) {
    final session = expectedGeneration ?? _service.sessionGeneration;
    if (!_service.isCurrentSession(session)) {
      return (ids: const [], completed: Future<void>.value());
    }
    // A repeated selection of the same path in this batch is not a second job.
    final paths = files.map((file) => file.path).where(isMediaPath).toSet();
    final jobs = <_GalleryUploadJob>[];
    for (final path in paths) {
      final draft = PendingPublicMedia(
        id: PendingPublicMediaService.newUploadId(),
        kind: PendingPublicMediaKind.venueGallery,
        venueId: venueId,
        localPath: path,
        isVideo: isVideoPath(path),
        createdAt: DateTime.now(),
        hasServerReceipt: false,
      );
      _service.prepareUpload(draft, expectedGeneration: session);
      jobs.add(_GalleryUploadJob(draft, File(path), session));
    }
    _queue.addAll(jobs);
    _drain();
    return (
      ids: List.unmodifiable(jobs.map((job) => job.draft.id)),
      completed: Future.wait(
        jobs.map((job) => job.completed.future),
      ).then((_) {}),
    );
  }

  void _drain() {
    // Bounded transfers keep a large selection from saturating memory/network.
    while (_active < 2 && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _active++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_GalleryUploadJob job) async {
    final releaseVideo = job.draft.isVideo
        ? MediaCompressor.retainVideoFiles()
        : null;
    try {
      if (!_service.isCurrentSession(job.session)) return;
      if (job.draft.isVideo) {
        final duration = await _videoDuration(job.file);
        if (duration <= Duration.zero) {
          throw const _GalleryPreparationFailure(
            'Could not read this video. Please choose another file.',
          );
        }
        if (duration > const Duration(seconds: 60)) {
          throw const _GalleryPreparationFailure(
            'Choose a video that is 60 seconds or shorter.',
          );
        }
      }
      if (!_service.isCurrentSession(job.session)) return;
      final prepared = job.draft.isVideo
          ? await _prepareVideo(job.file)
          : await _prepareImage(job.file);
      if (!_service.isCurrentSession(job.session)) return;
      if (await prepared.length() > 100 * 1024 * 1024) {
        throw const _GalleryPreparationFailure(
          'This file is too large. Please choose a smaller file.',
        );
      }
      File? thumbnail;
      if (job.draft.isVideo) {
        try {
          thumbnail = await _thumbnail(prepared);
        } catch (_) {}
      }
      final preview = job.draft.isVideo ? thumbnail : prepared;
      if (preview != null) {
        await _service.retainPreparedPreview(
          job.draft.id,
          preview.path,
          expectedGeneration: job.session,
        );
      }
      if (!_service.isCurrentSession(job.session)) return;
      await _sender(job.draft, prepared, thumbnail, job.session);
    } catch (error) {
      // Uncertain transport outcomes are already retained by runUpload and
      // must not turn into automatic retries or false success.
      _service.failPreparedUpload(
        job.draft.id,
        expectedGeneration: job.session,
        message: _failureMessage(error),
      );
    } finally {
      releaseVideo?.call();
      job.completed.complete();
      _active--;
      _drain();
    }
  }

  static String _failureMessage(Object error) {
    if (error is _GalleryPreparationFailure) return error.message;
    final text = error.toString();
    if (text.contains('60 seconds or shorter')) {
      return 'Choose a video that is 60 seconds or shorter.';
    }
    if (text.contains('(413)') || text.contains('File too large')) {
      return 'This file is too large. Please choose a smaller file.';
    }
    if (text.contains('(403)')) {
      return 'You do not have permission to add media to this venue.';
    }
    return 'This item could not be added to your gallery. Please choose another file.';
  }

  static Future<Duration> _readDuration(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize().timeout(const Duration(seconds: 15));
      return controller.value.duration;
    } catch (_) {
      throw const _GalleryPreparationFailure(
        'Could not read this video. Please choose another file.',
      );
    } finally {
      await controller.dispose();
    }
  }

  static Future<File?> _makeThumbnail(File file) async {
    final path = await VideoThumbnail.thumbnailFile(
      video: file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 720,
      quality: 80,
    );
    return path == null ? null : File(path);
  }

  static Future<void> _send(
    PendingPublicMedia draft,
    File file,
    File? thumbnail,
    int session,
  ) async {
    await VenueGalleryRepository().uploadItem(
      draft.venueId!,
      file,
      thumbnail: thumbnail,
      uploadSession: session,
      pendingDraft: draft,
    );
  }
}

class _GalleryUploadJob {
  _GalleryUploadJob(this.draft, this.file, this.session);
  final PendingPublicMedia draft;
  final File file;
  final int session;
  final completed = Completer<void>();
}

class _GalleryPreparationFailure implements Exception {
  const _GalleryPreparationFailure(this.message);
  final String message;
}
