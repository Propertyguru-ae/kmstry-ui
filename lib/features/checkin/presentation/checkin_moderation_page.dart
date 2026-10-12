import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

enum CheckinModerationFlowResult { approved, retake, cancelled }

enum _ReviewState {
  checking,
  delayed,
  review,
  reconnecting,
  rejected,
  failed,
  expired,
  activating,
  locationRequired,
}

/// A first Moment is different from an additional upload: room membership is
/// granted only by activation-status. Waiting is never converted into rejection.
class CheckinModerationPage extends StatefulWidget {
  const CheckinModerationPage({
    super.key,
    required this.checkinId,
    this.previewPath,
    this.repository,
    this.now,
    this.readLocation,
  });
  final String checkinId;
  final String? previewPath;
  final CheckinRepository? repository;
  @visibleForTesting
  final DateTime Function()? now;
  @visibleForTesting
  final Future<Position> Function()? readLocation;
  @override
  State<CheckinModerationPage> createState() => _CheckinModerationPageState();
}

class _CheckinModerationPageState extends State<CheckinModerationPage>
    with WidgetsBindingObserver {
  late final CheckinRepository _repository;
  late final DateTime _startedAt;
  late final int _session;
  Timer? _pollTimer;
  _ReviewState _state = _ReviewState.checking;
  bool _leaving = false;
  bool _finished = false;
  bool _polling = false;
  int _foregroundRevision = 0;
  String? _cancelError;
  String? _moderationMessage;
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  bool get _isCurrent =>
      mounted &&
      !_finished &&
      PendingPublicMediaService.instance.isCurrentSession(_session);
  bool get _canRetake =>
      _state == _ReviewState.rejected ||
      _state == _ReviewState.failed ||
      _state == _ReviewState.expired;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _canFinishHere =>
      _isCurrent &&
      !_leaving &&
      _cancelError == null &&
      _foreground &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? CheckinRepository();
    _startedAt = _now;
    _session = PendingPublicMediaService.instance.sessionGeneration;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_poll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foregroundRevision++;
    _pollTimer?.cancel();
    if (state == AppLifecycleState.resumed &&
        _state != _ReviewState.locationRequired) {
      unawaited(_poll());
    }
  }

  Future<CheckinActivationStatus?> _activate(
    CheckinActivationStatus ready,
    int foregroundRevision,
  ) async {
    if (!_canFinishHere || foregroundRevision != _foregroundRevision) {
      return null;
    }
    final itemId = ready.moderationItemId;
    if (itemId == null || itemId.isEmpty) {
      throw const FormatException('Missing exact moderation receipt');
    }
    setState(() => _state = _ReviewState.activating);
    Position position;
    try {
      position =
          await (widget.readLocation?.call() ??
                  Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.high,
                    timeLimit: const Duration(seconds: 8),
                  ))
              .timeout(const Duration(seconds: 9));
    } catch (_) {
      if (_canFinishHere && foregroundRevision == _foregroundRevision) {
        setState(() {
          _state = _ReviewState.locationRequired;
          _moderationMessage =
              'Your Moment is approved. Enable location access and try again to confirm you are still at the venue.';
        });
      }
      return null;
    }
    // Never send a late GPS result after cancel, logout, backgrounding or
    // leaving this route. The backend independently validates ownership/fix.
    if (!_canFinishHere || foregroundRevision != _foregroundRevision) {
      return null;
    }
    return _repository.activatePendingCheckin(
      checkinId: widget.checkinId,
      moderationItemId: itemId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      locationCapturedAt: position.timestamp,
    );
  }

  Future<void> _poll() async {
    if (!_isCurrent || _leaving || _polling || !_foreground) return;
    _pollTimer?.cancel();
    _polling = true;
    final foregroundRevision = _foregroundRevision;
    try {
      var status = await _repository
          .getCheckinActivationStatus(widget.checkinId)
          .timeout(const Duration(seconds: 10));
      if (!_isCurrent ||
          _leaving ||
          foregroundRevision != _foregroundRevision) {
        return;
      }
      if (status.checkinId != widget.checkinId) {
        throw const FormatException('Activation target mismatch');
      }
      if (status.state == CheckinActivationState.readyToActivate) {
        final activated = await _activate(status, foregroundRevision);
        if (activated == null ||
            !_canFinishHere ||
            foregroundRevision != _foregroundRevision) {
          return;
        }
        if (activated.checkinId != widget.checkinId) {
          throw const FormatException('Activation target mismatch');
        }
        status = activated;
      }
      // A status label or local preview is not proof this check-in can join.
      if (!mounted) return;
      if (status.canJoin &&
          status.state == CheckinActivationState.approved &&
          _canFinishHere) {
        _finished = true;
        Navigator.pop(context, CheckinModerationFlowResult.approved);
        return;
      }
      final next = switch (status.state) {
        CheckinActivationState.rejected => _ReviewState.rejected,
        CheckinActivationState.needsReview => _ReviewState.review,
        CheckinActivationState.error => _ReviewState.failed,
        CheckinActivationState.expired ||
        CheckinActivationState.activationExpired ||
        CheckinActivationState.cancelled => _ReviewState.expired,
        _ =>
          _now.difference(_startedAt) >= const Duration(seconds: 30)
              ? _ReviewState.delayed
              : _ReviewState.checking,
      };
      final message = status.userMessage?.trim();
      if (_state != next || _moderationMessage != message) {
        setState(() {
          _state = next;
          _moderationMessage = message;
        });
      }
    } on ApiException catch (error) {
      if (!_isCurrent ||
          _leaving ||
          foregroundRevision != _foregroundRevision) {
        return;
      }
      final code = error.data['errorCode'];
      setState(() {
        if (code == 'CHECKIN_ACTIVATION_UNAVAILABLE' ||
            error.statusCode == 404) {
          _state = _ReviewState.expired;
        } else if (code == 'CHECKIN_LOCATION_REQUIRED') {
          _state = _ReviewState.locationRequired;
          _moderationMessage =
              '${error.toString()} Your approved Moment is saved; you do not need to upload it again.';
        } else if (code == 'CHECKIN_APPROVED_MOMENT_REQUIRED') {
          _state = _ReviewState.failed;
          _moderationMessage =
              'The approved Moment is no longer available for this check-in. Please take a new Moment.';
        } else {
          _state = _ReviewState.reconnecting;
        }
      });
    } catch (_) {
      if (_isCurrent &&
          !_leaving &&
          foregroundRevision == _foregroundRevision) {
        setState(() => _state = _ReviewState.reconnecting);
      }
    } finally {
      _polling = false;
      if (_isCurrent &&
          !_canRetake &&
          !_leaving &&
          _foreground &&
          _cancelError == null &&
          _state != _ReviewState.locationRequired) {
        _pollTimer = Timer(
          _state == _ReviewState.reconnecting ||
                  _now.difference(_startedAt) >= const Duration(seconds: 30)
              ? const Duration(seconds: 10)
              : const Duration(seconds: 2),
          () => unawaited(_poll()),
        );
      }
    }
  }

  Future<void> _leave(CheckinModerationFlowResult result) async {
    if (!_isCurrent || _leaving) return;
    _pollTimer?.cancel();
    setState(() {
      _leaving = true;
      _cancelError = null;
    });
    try {
      try {
        await _repository
            .checkout(widget.checkinId)
            .timeout(const Duration(seconds: 10));
      } on ApiException catch (error) {
        if (error.statusCode != 404) rethrow;
      }
      if (!mounted || !_isCurrent) return;
      _finished = true;
      Navigator.pop(context, result);
    } catch (_) {
      if (!_isCurrent) return;
      setState(() {
        _leaving = false;
        _cancelError =
            'We could not confirm cancellation. Please check your connection and try again.';
      });
      // No automatic join or new check-in after an unconfirmed cancellation.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final bodyColor = isDark
        ? const Color(0xFFB4C2D8)
        : AppColors.lightTextSecondary;
    final copy = switch (_state) {
      _ReviewState.activating => (
        icon: Icons.location_searching_rounded,
        title: 'Finishing your check-in',
        text:
            'Your Moment is approved. We’re confirming you’re still at the venue.',
      ),
      _ReviewState.locationRequired => (
        icon: Icons.location_on_outlined,
        title: 'Confirm your location',
        text:
            _moderationMessage ??
            'Refresh your location to finish this check-in. You do not need to upload your Moment again.',
      ),
      _ReviewState.checking => (
        icon: Icons.hourglass_top_rounded,
        title: 'Checking your Moment',
        text:
            'Only you can see this for now. You’ll enter Who’s Here automatically when your check-in is ready.',
      ),
      _ReviewState.delayed => (
        icon: Icons.hourglass_bottom_rounded,
        title: 'Taking a little longer',
        text:
            'Your Moment is still being checked. Your check-in has not started. You do not need to upload it again.',
      ),
      _ReviewState.review => (
        icon: Icons.manage_search_rounded,
        title: 'Your Moment needs a review',
        text: _moderationMessage?.isNotEmpty == true
            ? '$_moderationMessage Your check-in has not started. You can wait here or cancel this check-in.'
            : 'Your Moment is not visible to others yet and you have not joined the room. You can wait here or cancel this check-in.',
      ),
      _ReviewState.reconnecting => (
        icon: Icons.wifi_rounded,
        title: 'Reconnecting',
        text:
            'We are checking your check-in status. This is not a rejection. Please do not upload your Moment again.',
      ),
      _ReviewState.rejected => (
        icon: Icons.add_a_photo_rounded,
        title: 'Let’s try another Moment',
        text: _moderationMessage?.isNotEmpty == true
            ? '$_moderationMessage Your check-in has not started.'
            : 'This Moment did not meet our content guidelines and was not shared. Your check-in has not started.',
      ),
      _ReviewState.failed => (
        icon: Icons.sync_problem_rounded,
        title: 'We couldn’t finish this check',
        text: _moderationMessage?.isNotEmpty == true
            ? '$_moderationMessage Your check-in has not started.'
            : 'Your check-in has not started. You can try another Moment or cancel and try later.',
      ),
      _ReviewState.expired => (
        icon: Icons.timer_off_rounded,
        title: 'Start a fresh check-in',
        text:
            'This check-in can no longer join the room. Start again so we can confirm you are still at the venue.',
      ),
    };
    final showPreview = !_canRetake && widget.previewPath != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(CheckinModerationFlowResult.cancelled));
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        // Check-in akışının (Check in sayfası) başlık düzeni.
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Cancel check-in',
            onPressed: _leaving
                ? null
                : () => _leave(CheckinModerationFlowResult.cancelled),
            icon: Icon(Icons.close, color: colors.onSurface, size: 28),
          ),
          title: Text(
            'Check in',
            style: TextStyle(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                child: Column(
                  children: [
                    if (showPreview)
                      _MomentPreview(
                        path: widget.previewPath!,
                        isDark: isDark,
                        placeholder: _StatusIcon(icon: copy.icon),
                      )
                    else
                      _StatusIcon(icon: copy.icon),
                    const SizedBox(height: 26),
                    Text(
                      copy.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      copy.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 14.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_cancelError != null) ...[
                      const SizedBox(height: 20),
                      BrandedNoticeCard(
                        title: 'Check-in not cancelled yet',
                        message: _cancelError!,
                        tone: BrandedNoticeTone.error,
                        icon: Icons.wifi_off_rounded,
                        compact: true,
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (_state == _ReviewState.locationRequired &&
                        _cancelError == null) ...[
                      _PrimaryIconButton(
                        icon: Icons.location_searching_rounded,
                        label: 'Try again',
                        onPressed: _leaving || _polling
                            ? null
                            : () => unawaited(_poll()),
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (_canRetake) ...[
                      _PrimaryIconButton(
                        icon: Icons.photo_camera_rounded,
                        label: 'Retake Moment',
                        onPressed: _leaving
                            ? null
                            : () => _leave(CheckinModerationFlowResult.retake),
                      ),
                      const SizedBox(height: 6),
                    ],
                    TextButton(
                      onPressed: _leaving
                          ? null
                          : () => _leave(CheckinModerationFlowResult.cancelled),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: bodyColor,
                      ),
                      child: Text(
                        _leaving ? 'Cancelling check-in…' : 'Cancel check-in',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uygulamanın standart popup'larındaki gradyan ikon kutusu, sayfa boyutunda.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    height: 88,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.blue, AppColors.magenta],
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.magenta.withValues(alpha: 0.35),
          blurRadius: 26,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Icon(icon, color: Colors.white, size: 42),
  );
}

/// Bekleme sırasında kullanıcının kendi Moment'i; yalnızca ona görünür.
class _MomentPreview extends StatelessWidget {
  const _MomentPreview({
    required this.path,
    required this.isDark,
    required this.placeholder,
  });
  final String path;
  final bool isDark;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) => Container(
    width: 200,
    height: 250,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(23),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 600,
            errorBuilder: (_, _, _) => ColoredBox(
              color: isDark ? const Color(0xFF121A2B) : const Color(0xFFF1F4F9),
              child: Center(child: placeholder),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, color: Colors.white, size: 13),
                    SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Only visible to you',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Uygulamanın standart birincil butonu (düz mavi), ikonlu.
class _PrimaryIconButton extends StatelessWidget {
  const _PrimaryIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? 0.5 : 1,
    child: SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.blue,
          boxShadow: [
            BoxShadow(
              color: AppColors.blue.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
