import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

enum PerformancePage {
  venueHome,
  venueProfile,
  venueDetail,
  guests,
  whoIsHere,
  events,
  notifications,
  analytics,
  followers,
  team,
  settings,
  venueManage,
}

// Route segments must be code-owned, never user names, IDs or query values.
const _fixedSegments = {
  'auth',
  'me',
  'refresh',
  'logout',
  'users',
  'venues',
  'owner-stats',
  'owner-profile',
  'identity',
  'detail',
  'upcoming-events',
  'owner-guests',
  'owner-dashboard',
  'checkin-stats',
  'checkins',
  'profile',
  'profile-photos',
  'photos',
  'media',
  'stories',
  'venue-stories',
  'gallery',
  'events',
  'calendar',
  'notifications',
  'read',
  'unread-count',
  'matches',
  'chats',
  'messages',
  'content-moderation',
  'my',
  'items',
  'permissions',
  'members',
  'followers',
  'analytics',
  'reports',
  'roles',
  'role-permissions',
  'partnerships',
  'activation-status',
};

String performanceRoute(String path) {
  final uri = Uri.tryParse(path);
  if (uri == null) return 'unknown';
  return '/${uri.path.split('/').where((part) => part.isNotEmpty).map((part) => _fixedSegments.contains(part) ? part : ':id').take(12).join('/')}';
}

class _RequestSpan {
  final clock = Stopwatch()..start();
  int? headersMs;
  int? status;
  int responseBytes = 0;
  int responses = 0;
  String? backendId;
}

class PerformanceDiagnostics {
  static const _configured = bool.fromEnvironment('PERFORMANCE_DEBUG');
  static final _requestKey = Object();
  static int _loads = 0;
  static int _transfers = 0;
  static int _videoTransfers = 0;
  static int _pending = 0;

  @visibleForTesting
  static bool? enabledOverride;
  @visibleForTesting
  static void Function(Map<String, Object?>)? sinkOverride;
  static bool get enabled => enabledOverride ?? _configured;

  static void emit(Map<String, Object?> record) {
    if (!enabled) return;
    try {
      final result = {
        ...record,
        'uploadTransfers': _transfers,
        'videoTransfers': _videoTransfers,
        'moderationPending': _pending,
      };
      final sink = sinkOverride;
      if (sink != null) {
        sink(result);
      } else {
        debugPrint('[Performance] ${jsonEncode(result)}');
      }
    } catch (_) {
      // An observer cannot fail HTTP, a page load or an upload.
    }
  }

  static void setUploadCounts({
    required int transfers,
    required int videos,
    required int pending,
  }) {
    if (!enabled) return;
    _transfers = transfers;
    _videoTransfers = videos;
    _pending = pending;
  }

  static void headersReady() {
    final span = Zone.current[_requestKey] as _RequestSpan?;
    if (span != null) span.headersMs ??= span.clock.elapsedMilliseconds;
  }

  static void response({
    required int status,
    required int bytes,
    String? backendId,
  }) {
    final span = Zone.current[_requestKey] as _RequestSpan?;
    if (span == null) return;
    span.status = status;
    span.responseBytes += bytes;
    span.responses++;
    span.backendId =
        backendId != null && RegExp(r'^[a-f0-9-]{36}$').hasMatch(backendId)
        ? backendId
        : null;
  }

  static Future<T> request<T>(
    String method,
    String path,
    Future<T> Function() operation,
  ) {
    if (!enabled) return operation();
    final span = _RequestSpan();
    final transfersAtStart = _transfers;
    final pendingAtStart = _pending;
    return runZoned(() async {
      String? errorType;
      try {
        return await operation();
      } catch (error) {
        errorType = error.runtimeType.toString(); // Never log error messages.
        rethrow;
      } finally {
        final elapsed = span.clock.elapsedMilliseconds;
        emit({
          'event': 'api_performance',
          'uploadTransfersAtStart': transfersAtStart,
          'moderationPendingAtStart': pendingAtStart,
          'method': method,
          'route': performanceRoute(path),
          'durationMs': elapsed,
          'headersMs': span.headersMs,
          // Includes response read/decode and any retries, not network alone.
          'afterHeadersMs': span.headersMs == null
              ? null
              : elapsed - span.headersMs!,
          'status': span.status,
          'responseBytes': span.responseBytes,
          'responses': span.responses,
          'backendRequestId': span.backendId,
          'errorType': errorType,
        });
      }
    }, zoneValues: {_requestKey: span});
  }

  static Future<T> pageLoad<T>(
    PerformancePage page,
    Future<T> Function() operation, {
    required bool Function() isMounted,
  }) async {
    if (!enabled) return operation();
    final id = ++_loads;
    final clock = Stopwatch()..start();
    emit({'event': 'page_load_started', 'page': page.name, 'load': id});
    try {
      return await operation();
    } finally {
      // "Completed" is not a success claim: existing screens may handle errors.
      emit({
        'event': 'page_load_completed',
        'page': page.name,
        'load': id,
        'durationMs': clock.elapsedMilliseconds,
        'mounted': isMounted(),
      });
      if (isMounted()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (isMounted()) {
            emit({
              'event': 'page_post_load_frame',
              'page': page.name,
              'load': id,
              'durationMs': clock.elapsedMilliseconds,
            });
          }
        });
      }
    }
  }

  static Future<T> mediaTransfer<T>({
    required String kind,
    required bool video,
    required Future<T> Function() operation,
  }) async {
    if (!enabled) return operation();
    final clock = Stopwatch()..start();
    String? errorType;
    try {
      return await operation();
    } catch (error) {
      errorType = error.runtimeType.toString();
      rethrow;
    } finally {
      emit({
        'event': 'media_transfer_completed',
        'kind': kind,
        'video': video,
        'durationMs': clock.elapsedMilliseconds,
        'errorType': errorType,
      });
    }
  }
}

/// Records first UI frame only, separately from data completion. It does not
/// mean all network images have loaded. No loading UI/navigation is changed.
class PerformancePageProbe extends StatefulWidget {
  const PerformancePageProbe({
    super.key,
    required this.page,
    required this.child,
  });
  final PerformancePage page;
  final Widget child;
  @override
  State<PerformancePageProbe> createState() => _PerformancePageProbeState();
}

class _PerformancePageProbeState extends State<PerformancePageProbe> {
  @override
  void initState() {
    super.initState();
    if (!PerformanceDiagnostics.enabled) return;
    final clock = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PerformanceDiagnostics.emit({
          'event': 'page_first_frame',
          'page': widget.page.name,
          'durationMs': clock.elapsedMilliseconds,
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
