/// In-memory cache of viewed venue story IDs for the current app session.
/// Persists across page navigations; cleared on app restart (acceptable since
/// stories expire in 24h and backend now records all views including poster's).
class VenueStoryViewedCache {
  VenueStoryViewedCache._();
  static final instance = VenueStoryViewedCache._();

  final _viewedIds = <String>{};

  void mark(String storyId) => _viewedIds.add(storyId);
  void markAll(Iterable<String> ids) => _viewedIds.addAll(ids);
  bool isViewed(String storyId) => _viewedIds.contains(storyId);
  void clear() => _viewedIds.clear();
}
