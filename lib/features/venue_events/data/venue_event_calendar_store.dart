import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

import 'venue_event_calendar_entry.dart';
import 'venue_event_mutation.dart';
import 'venue_event_deletion.dart';
import 'venue_event_repository.dart';

/// Page-owned reads, never a global user/venue/environment cache. Calendar
/// metadata can paint immediately while the selected month's media is loading.
/// Mutations revoke old in-flight reads so they cannot resurrect removed events.
class VenueEventCalendarStore extends ChangeNotifier {
  VenueEventCalendarStore({
    required this.venueId,
    required this.repository,
    required bool Function() isCurrentSession,
    List<VenueUpcomingEvent> seed = const [],
    DateTime Function()? clock,
  }) : _isCurrentSession = isCurrentSession,
       _clock = clock ?? DateTime.now {
    _putEvents(seed);
    _rebuildDays();
  }

  final String venueId;
  final VenueEventRepository repository;
  final bool Function() _isCurrentSession;
  final DateTime Function() _clock;
  static const _freshFor = Duration(seconds: 60);
  final _events = <String, VenueUpcomingEvent>{};
  final _calendar = <String, VenueEventCalendarEntry>{};
  final _loadedMonths = <String, DateTime>{};
  final _monthReads = <String, Future<void>>{};
  final _monthErrors = <String, Object>{};
  Future<void>? _calendarRead;
  DateTime? _calendarLoadedAt;
  Set<String> _days = {};
  int _revision = 0;
  bool _disposed = false;
  bool get _current => !_disposed && _isCurrentSession();

  List<VenueUpcomingEvent> get events =>
      _current ? _events.values.toList() : [];
  Set<String> get daysWithEvents => _current ? _days : const {};

  static String dayKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month}-${local.day}';
  }

  static String _monthKey(DateTime date) => '${date.year}-${date.month}';
  bool _fresh(DateTime? at) =>
      at != null && _clock().difference(at) < _freshFor;

  Iterable<String> _selectionMonths(DateTime start, DateTime? end) sync* {
    final last = end ?? start;
    for (
      var month = DateTime(start.year, start.month);
      !month.isAfter(DateTime(last.year, last.month));
      month = DateTime(month.year, month.month + 1)
    ) {
      yield _monthKey(month);
    }
  }

  /// A seed/summary is not evidence that a selected day has no events.
  /// Keep successful empty results distinct from pending or failed reads.
  bool hasLoadedSelection(DateTime start, DateTime? end) =>
      _current && _selectionMonths(start, end).every(_loadedMonths.containsKey);

  Object? selectionError(DateTime start, DateTime? end) {
    if (!_current) return null;
    for (final key in _selectionMonths(start, end)) {
      final error = _monthErrors[key];
      if (error != null) return error;
    }
    return null;
  }

  void _putEvents(Iterable<VenueUpcomingEvent> events) {
    for (final event in events) {
      _events[event.id] = event;
      _calendar[event.id] = VenueEventCalendarEntry(
        id: event.id,
        startAt: event.startAt,
        recurringRuleId: event.recurringRuleId,
      );
    }
  }

  void _rebuildDays() {
    _days = Set.unmodifiable(_calendar.values.map((e) => dayKey(e.startAt)));
  }

  Future<void> loadCalendar() {
    if (!_current || _fresh(_calendarLoadedAt)) return Future.value();
    final existing = _calendarRead;
    if (existing != null) return existing;
    final revision = _revision;
    late final Future<void> read;
    read =
        (() async {
          final entries = await repository.getEventCalendar(venueId);
          if (!_current || revision != _revision) return;
          _calendar
            ..clear()
            ..addEntries(entries.map((e) => MapEntry(e.id, e)));
          _calendarLoadedAt = _clock();
          _rebuildDays();
          notifyListeners();
        })().whenComplete(() {
          if (identical(_calendarRead, read)) _calendarRead = null;
        });
    return _calendarRead = read;
  }

  Future<void> loadMonth(DateTime date) {
    if (!_current) return Future.value();
    final month = DateTime(date.year, date.month);
    final key = _monthKey(month);
    if (_fresh(_loadedMonths[key])) return Future.value();
    final existing = _monthReads[key];
    if (existing != null) return existing;
    final revision = _revision;
    _monthErrors.remove(key);
    late final Future<void> read;
    read =
        (() async {
          List<VenueUpcomingEvent> entries;
          try {
            entries = await repository.listEventMonth(venueId, month);
          } catch (error) {
            if (_current && revision == _revision) {
              _monthErrors[key] = error;
            }
            rethrow;
          }
          if (!_current || revision != _revision) return;
          bool belongs(DateTime start) => _monthKey(start.toLocal()) == key;
          _events.removeWhere((_, e) => belongs(e.startAt));
          _calendar.removeWhere((_, e) => belongs(e.startAt));
          _putEvents(entries);
          _loadedMonths[key] = _clock();
          _rebuildDays();
          notifyListeners();
        })().whenComplete(() {
          if (identical(_monthReads[key], read)) _monthReads.remove(key);
          if (_current && revision == _revision) notifyListeners();
        });
    _monthReads[key] = read;
    notifyListeners();
    return read;
  }

  /// Any selected range remains accessible. At most two month reads run at
  /// once, avoiding a burst of requests if a user selects a multi-year range.
  Future<void> loadSelection(DateTime start, DateTime? end) async {
    final last = end ?? start;
    final months = <DateTime>[];
    for (
      var m = DateTime(start.year, start.month);
      !m.isAfter(DateTime(last.year, last.month));
      m = DateTime(m.year, m.month + 1)
    ) {
      months.add(m);
    }
    final revision = _revision;
    var index = 0;
    Future<void> drain() async {
      while (_current && revision == _revision && index < months.length) {
        final month = months[index++];
        // One failed month must not hide later months in the chosen range.
        try {
          await loadMonth(month);
        } catch (_) {}
      }
    }

    await Future.wait([drain(), drain()]);
  }

  void invalidate() {
    _revision++;
    _loadedMonths.clear();
    _monthReads.clear();
    _monthErrors.clear();
    _calendarRead = null;
    _calendarLoadedAt = null;
  }

  void created(List<VenueUpcomingEvent> events) {
    if (!_current) return;
    invalidate();
    _putEvents(events);
    _changed();
  }

  void updated(VenueEventMutation mutation) {
    if (!_current) return;
    invalidate();
    for (final id in mutation.removedEventIds) {
      _events.remove(id);
      _calendar.remove(id);
    }
    _putEvents(mutation.events);
    _changed();
  }

  void deleted(VenueUpcomingEvent event, {required bool series}) {
    if (!_current) return;
    invalidate();
    bool remove(String id, String? ruleId) =>
        series && event.recurringRuleId != null
        ? ruleId == event.recurringRuleId
        : id == event.id;
    _events.removeWhere((id, e) => remove(id, e.recurringRuleId));
    _calendar.removeWhere((id, e) => remove(id, e.recurringRuleId));
    _changed();
  }

  void removed(VenueEventDeletion deletion) {
    if (!_current) return;
    final loadedMonths = Map<String, DateTime>.of(_loadedMonths);
    invalidate();
    // This exact deletion cannot add unknown events. Keep prior complete reads
    // authoritative, while invalidation revokes older in-flight responses.
    _loadedMonths.addAll(loadedMonths);
    bool remove(String id, String? ruleId) =>
        deletion.removedEventIds.contains(id) ||
        (deletion.removedRecurringRuleId != null &&
            ruleId == deletion.removedRecurringRuleId);
    _events.removeWhere((id, event) => remove(id, event.recurringRuleId));
    _calendar.removeWhere((id, event) => remove(id, event.recurringRuleId));
    _changed();
  }

  void _changed() {
    _rebuildDays();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    invalidate();
    super.dispose();
  }
}
