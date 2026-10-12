import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import 'avatar_upload_repository.dart';
import 'pending_public_media.dart';

typedef AvatarSender =
    Future<void> Function(PendingPublicMedia draft, File file, int session);

/// Owns photo preparation/transfer after the picker route has gone away.
class AvatarUploadCoordinator {
  AvatarUploadCoordinator._({
    PendingPublicMediaService? service,
    Future<File> Function(File)? prepare,
    AvatarSender? sender,
  }) : _service = service ?? PendingPublicMediaService.instance,
       _prepare =
           prepare ??
           ((file) => MediaCompressor.compressImage(file, maxDimension: 1080)),
       _sender = sender ?? _send;
  static final instance = AvatarUploadCoordinator._();
  @visibleForTesting
  AvatarUploadCoordinator.forTest({
    required PendingPublicMediaService service,
    required Future<File> Function(File) prepare,
    required AvatarSender sender,
  }) : this._(service: service, prepare: prepare, sender: sender);
  final PendingPublicMediaService _service;
  final Future<File> Function(File) _prepare;
  final AvatarSender _sender;

  bool canSelect(PendingPublicMediaKind kind, {String? venueId}) => !_service
      .forKind(kind, venueId: venueId)
      .any(
        (item) =>
            item.state == PendingPublicMediaState.preparing ||
            item.state == PendingPublicMediaState.uploading ||
            (!item.hasServerReceipt &&
                item.state == PendingPublicMediaState.connectionIssue),
      );

  ({String id, Future<void> completed})? share({
    required File file,
    required PendingPublicMediaKind kind,
    String? venueId,
    required int expectedGeneration,
  }) {
    if (!_service.isCurrentSession(expectedGeneration)) return null;
    if (kind != PendingPublicMediaKind.personalAvatar &&
        kind != PendingPublicMediaKind.venueAvatar) {
      throw ArgumentError('Not an avatar');
    }
    if (kind == PendingPublicMediaKind.venueAvatar &&
        (venueId?.isEmpty ?? true)) {
      throw ArgumentError('Venue required');
    }
    if (!canSelect(kind, venueId: venueId)) return null;
    // Only the latest candidate matters for this photo slot. This does not
    // delete or cancel server media; the backend enforces the replacement order.
    for (final old in _service.forKind(kind, venueId: venueId)) {
      _service.dismiss(old.id);
    }
    final draft = PendingPublicMedia(
      id: PendingPublicMediaService.newUploadId(),
      kind: kind,
      venueId: venueId,
      localPath: file.path,
      isVideo: false,
      createdAt: DateTime.now(),
      hasServerReceipt: false,
    );
    _service.prepareUpload(draft, expectedGeneration: expectedGeneration);
    return (
      id: draft.id,
      completed: _complete(draft, file, expectedGeneration),
    );
  }

  Future<void> _complete(
    PendingPublicMedia draft,
    File file,
    int session,
  ) async {
    try {
      final prepared = await _prepare(file);
      if (!_service.isCurrentSession(session)) return;
      if (await prepared.length() > 10 * 1024 * 1024) {
        throw const PublicMediaUploadRejected('PHOTO_TOO_LARGE');
      }
      await _service.retainPreparedPreview(
        draft.id,
        prepared.path,
        expectedGeneration: session,
      );
      if (!_service.isCurrentSession(session)) return;
      await _sender(draft, prepared, session);
    } catch (_) {
      _service.failPreparedUpload(
        draft.id,
        expectedGeneration: session,
        message:
            'Your photo could not be updated. Please choose another photo.',
      );
    }
  }

  static Future<void> _send(
    PendingPublicMedia draft,
    File file,
    int session,
  ) async {
    await AvatarUploadRepository().upload(
      file: file,
      draft: draft,
      session: session,
    );
  }
}
