import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../content_moderation/data/pending_public_media.dart';
import 'checkin_profile_model.dart';

class OwnerMomentEntry {
  const OwnerMomentEntry({this.media, this.pending});
  final CheckinProfileMedia? media;
  final PendingPublicMedia? pending;
  String get key => pending?.uploadId ?? pending?.id ?? media!.id;
}

/// Approved Moments and this owner's local previews share one navigation list.
/// An approved receipt is replaced only by its exact canonical media record.
class OwnerMomentSequence extends ChangeNotifier {
  OwnerMomentSequence({
    required this.checkinId,
    required List<CheckinProfileMedia> published,
    required this.uploads,
    required this.loadPublished,
  }) : _published = List.of(published),
       _session = uploads.sessionGeneration {
    uploads.changes.addListener(_sync);
    _sync();
  }

  final String checkinId;
  final PendingPublicMediaService uploads;
  final Future<CheckinProfile> Function() loadPublished;
  final int _session;
  List<CheckinProfileMedia> _published;
  Map<String, PendingPublicMedia> _pending = {};
  final Set<String> _removed = {};
  final Map<String, String> _receiptIds = {};
  Timer? _retry;
  bool _loading = false;
  bool _disposed = false;
  bool get sessionValid => uploads.isCurrentSession(_session);
  List<CheckinProfileMedia> get published => List.unmodifiable(_published);

  List<OwnerMomentEntry> get entries {
    if (!sessionValid) return [];
    final pending = _pending.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [
      for (final media in _published) OwnerMomentEntry(media: media),
      for (final item in pending) OwnerMomentEntry(pending: item),
    ];
  }

  int indexOf(String key) => entries.indexWhere(
    (entry) => entry.key == key || entry.media?.id == _receiptIds[key],
  );

  void removePublished(String id) {
    _removed.add(id);
    _published.removeWhere((item) => item.id == id);
    _sync();
  }

  void updatePublished(List<CheckinProfileMedia> media) {
    _published = List.of(media);
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    if (!sessionValid) {
      _published.clear();
      _pending.clear();
      _retry?.cancel();
      notifyListeners();
      return;
    }
    final ids = _published.map((item) => item.id).toSet();
    final next = <String, PendingPublicMedia>{
      for (final item in uploads.forKind(PendingPublicMediaKind.checkinMoment))
        if (item.checkinId == checkinId &&
            !ids.contains(item.id) &&
            !_removed.contains(item.id))
          (item.uploadId ?? item.id): item,
    };
    for (final entry in _pending.entries) {
      if (!next.containsKey(entry.key) &&
          !ids.contains(entry.value.id) &&
          !_removed.contains(entry.value.id) &&
          uploads.wasPublished(entry.value.id)) {
        next[entry.key] = entry.value.withState(
          PendingPublicMediaState.published,
        );
      }
    }
    for (final entry in next.entries) {
      _receiptIds[entry.key] = entry.value.id;
    }
    _pending = next;
    notifyListeners();
    if (_pending.values.any((item) => uploads.wasPublished(item.id))) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (_disposed || !sessionValid || _loading || _retry?.isActive == true) {
      return;
    }
    _loading = true;
    try {
      final profile = await loadPublished();
      if (_disposed || !sessionValid || profile.checkin.id != checkinId) return;
      _published = profile.media
          .where((item) => !_removed.contains(item.id))
          .toList();
    } catch (_) {
      // Keep owner previews during a temporary canonical read failure.
    } finally {
      _loading = false;
    }
    if (_disposed || !sessionValid) return;
    // Set the retry before sync so an unresolved publication cannot loop.
    _retry = Timer(const Duration(seconds: 5), _sync);
    _sync();
    if (!_pending.values.any((item) => uploads.wasPublished(item.id))) {
      _retry?.cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    uploads.changes.removeListener(_sync);
    super.dispose();
  }
}
