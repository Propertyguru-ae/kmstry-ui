import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_item.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_repository.dart';

class ContentModerationStatusPage extends StatefulWidget {
  const ContentModerationStatusPage({super.key, this.repository});

  final ContentModerationRepository? repository;

  @override
  State<ContentModerationStatusPage> createState() =>
      _ContentModerationStatusPageState();
}

class _ContentModerationStatusPageState
    extends State<ContentModerationStatusPage> {
  static const int _historyDays = 30;
  static const int _pageSize = 20;
  late final ContentModerationRepository _repository;
  List<ContentModerationItem> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _total = 0;
  int _requestGeneration = 0;
  bool _loadMoreFailed = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ContentModerationRepository();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    final request = ++_requestGeneration;
    _loadingMore = false;
    _loadMoreFailed = false;
    if (refresh) {
      _page = 1;
    } else if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final result = await _repository.listMyItems(
        page: _page,
        limit: _pageSize,
        recentDays: _historyDays,
      );
      if (!mounted || request != _requestGeneration) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _requestGeneration) return;
      setState(() {
        _error = 'Content review status could not be loaded.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    final request = _requestGeneration;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final nextPage = _page + 1;
      final result = await _repository.listMyItems(
        page: nextPage,
        limit: _pageSize,
        recentDays: _historyDays,
      );
      if (!mounted || request != _requestGeneration) return;
      setState(() {
        _page = nextPage;
        _items = [..._items, ...result.items];
        _total = result.total;
      });
    } catch (_) {
      if (mounted && request == _requestGeneration) {
        setState(() => _loadMoreFailed = true);
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Content review')),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.blue.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Public media is checked before it appears. '
                      'This page shows uploads from the last 30 days. '
                      'Private message media is not shown here.',
                      style: TextStyle(
                        height: 1.4,
                        color: colors.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorState(message: _error!, onRetry: _load)
            else if (_items.isEmpty)
              const _EmptyState()
            else ...[
              ..._items.map((item) => _ModerationItemCard(item: item)),
              if (_loadMoreFailed)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Could not load more. Please try again.'),
                ),
              if (_items.length < _total)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: _loadingMore ? null : _loadMore,
                    child: _loadingMore
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Load more'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModerationItemCard extends StatelessWidget {
  const _ModerationItemCard({required this.item});

  final ContentModerationItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = _statusPresentation(
      item.status,
      colors,
      processingIssue: item.processingIssue,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(status.icon, color: status.color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _targetLabel(item.targetType),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.mediaType == 'VIDEO' ? 'Video' : 'Photo',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (item.userMessage?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              item.userMessage!.trim(),
              style: TextStyle(
                height: 1.35,
                color: colors.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _formatDate(item.updatedAt ?? item.createdAt),
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 52,
            color: AppColors.teal.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 14),
          const Text(
            'Nothing needs your attention',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Uploads disappear from this list after approval.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

({String label, IconData icon, Color color}) _statusPresentation(
  String status,
  ColorScheme colors, {
  bool processingIssue = false,
}) {
  if (status == 'NEEDS_REVIEW' && processingIssue) {
    return (
      label: 'Awaiting review',
      icon: Icons.sync_problem_rounded,
      color: AppColors.orange,
    );
  }
  return switch (status) {
    'PENDING' => (
      label: 'Queued',
      icon: Icons.schedule_rounded,
      color: AppColors.blue,
    ),
    'PROCESSING' => (
      label: 'Checking',
      icon: Icons.manage_search_rounded,
      color: AppColors.blue,
    ),
    'NEEDS_REVIEW' => (
      label: 'Manual review',
      icon: Icons.fact_check_outlined,
      color: AppColors.orange,
    ),
    'REJECTED' => (
      label: 'Not published',
      icon: Icons.block_rounded,
      color: colors.error,
    ),
    'ERROR' => (
      label: 'Could not process',
      icon: Icons.sync_problem_rounded,
      color: AppColors.orange,
    ),
    'APPROVED' => (
      label: 'Check complete',
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.tealDark,
    ),
    _ => (
      label: status,
      icon: Icons.info_outline_rounded,
      color: colors.onSurfaceVariant,
    ),
  };
}

String _targetLabel(String targetType) {
  return switch (targetType) {
    'USER_PROFILE_PHOTO' => 'Profile photo',
    'CHECKIN_AVATAR' => 'Check-in avatar',
    'CHECKIN_PHOTO' => 'Check-in photo',
    'CHECKIN_MEDIA' => 'Check-in media',
    'PERSONAL_STORY' => 'Personal story',
    'VENUE_STORY' => 'Venue story',
    'VENUE_COVER' => 'Venue cover',
    'VENUE_GALLERY' => 'Venue gallery',
    'EVENT_PHOTO' => 'Event photo',
    'VENUE_OFFER' => 'Venue offer',
    _ => 'Public upload',
  };
}

String _formatDate(DateTime? raw) {
  if (raw == null) return '';
  final date = raw.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}
