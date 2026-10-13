import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import 'venue_event_repository.dart';

typedef EventPhotoSender =
    Future<void> Function(PendingPublicMedia draft, File file, int session);

/// Session-owned work: closing the editor/detail page never cancels a photo.
class EventPhotoUploadCoordinator {
  EventPhotoUploadCoordinator._({
    PendingPublicMediaService? service,
    Future<File> Function(File)? prepare,
    EventPhotoSender? sender,
  }) : _service = service ?? PendingPublicMediaService.instance,
       _prepare = prepare ?? MediaCompressor.compressImage,
       _sender = sender ?? _send;
  static final instance = EventPhotoUploadCoordinator._();
  @visibleForTesting
  EventPhotoUploadCoordinator.forTest({
    required PendingPublicMediaService service,
    required Future<File> Function(File) prepare,
    required EventPhotoSender sender,
  }) : this._(service: service, prepare: prepare, sender: sender);
  final PendingPublicMediaService _service;
  final Future<File> Function(File) _prepare;
  final EventPhotoSender _sender;
  final Queue<_EventPhotoJob> _queue = Queue();
  final Set<String> _activeTargets = {};

  ({List<String> ids, Future<void> completed}) share({
    required String venueId,
    String? eventId,
    String? recurringRuleId,
    required List<File> files,
    required int expectedGeneration,
  }) {
    if (!_service.isCurrentSession(expectedGeneration)) {
      return (ids: const [], completed: Future.value());
    }
    if (venueId.isEmpty ||
        ((eventId?.isEmpty ?? true) == (recurringRuleId?.isEmpty ?? true))) {
      throw ArgumentError('Exactly one event or recurring series is required');
    }
    final jobs = files.map((file) => file.path).toSet().map((path) {
      final draft = PendingPublicMedia(
        id: PendingPublicMediaService.newUploadId(),
        kind: PendingPublicMediaKind.eventPhoto,
        venueId: venueId,
        eventId: eventId,
        recurringRuleId: recurringRuleId,
        localPath: path,
        isVideo: false,
        createdAt: DateTime.now(),
        hasServerReceipt: false,
      );
      _service.prepareUpload(draft, expectedGeneration: expectedGeneration);
      return _EventPhotoJob(draft, File(path), expectedGeneration);
    }).toList();
    _queue.addAll(jobs);
    _drain();
    return (
      ids: List.unmodifiable(jobs.map((job) => job.draft.id)),
      completed: Future.wait(jobs.map((job) => job.done.future)).then((_) {}),
    );
  }

  void _drain() {
    // Preserve selection order for a cover/series and bound total transfers.
    while (_activeTargets.length < 2) {
      final candidates = _queue.where(
        (job) => !_activeTargets.contains(job.target),
      );
      if (candidates.isEmpty) return;
      final job = candidates.first;
      _queue.remove(job);
      _activeTargets.add(job.target);
      unawaited(_run(job));
    }
  }

  Future<void> _run(_EventPhotoJob job) async {
    try {
      if (!_service.isCurrentSession(job.session) ||
          _service.isEventPhotoTargetDeleted(job.draft)) {
        return;
      }
      final file = await _prepare(job.file);
      if (!_service.isCurrentSession(job.session) ||
          _service.isEventPhotoTargetDeleted(job.draft)) {
        return;
      }
      if (await file.length() > 20 * 1024 * 1024) {
        throw const PublicMediaUploadRejected('PHOTO_TOO_LARGE');
      }
      await _service.retainPreparedPreview(
        job.draft.id,
        file.path,
        expectedGeneration: job.session,
      );
      if (!_service.isCurrentSession(job.session)) return;
      await _sender(job.draft, file, job.session);
    } catch (error) {
      _service.failPreparedUpload(
        job.draft.id,
        expectedGeneration: job.session,
        message: error.toString().contains('(400)')
            ? 'This event may already have three photos. Refresh it before adding another.'
            : 'This event photo could not be shared. Please choose another photo.',
      );
    } finally {
      job.done.complete();
      _activeTargets.remove(job.target);
      _drain();
    }
  }

  static Future<void> _send(
    PendingPublicMedia draft,
    File file,
    int session,
  ) async {
    final repo = VenueEventRepository();
    if (draft.recurringRuleId != null) {
      await repo.uploadRecurringPhoto(
        venueId: draft.venueId!,
        ruleId: draft.recurringRuleId!,
        file: file,
        pendingDraft: draft,
        uploadSession: session,
      );
    } else {
      await repo.uploadPhoto(
        venueId: draft.venueId!,
        eventId: draft.eventId!,
        file: file,
        pendingDraft: draft,
        uploadSession: session,
      );
    }
  }
}

class _EventPhotoJob {
  _EventPhotoJob(this.draft, this.file, this.session);
  final PendingPublicMedia draft;
  final File file;
  final int session;
  final done = Completer<void>();
  String get target =>
      '${draft.venueId}:${draft.recurringRuleId ?? draft.eventId}';
}
