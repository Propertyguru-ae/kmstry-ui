import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/network_error.dart';
import 'package:kmstry_frontend/core/ui/connection_error_view.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_model.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_reauthentication.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class DataExportPage extends StatefulWidget {
  const DataExportPage({super.key, this.repository, this.reauthentication});

  final DataExportRepository? repository;
  final DataExportReauthentication? reauthentication;

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  late final DataExportRepository _repository;
  late final DataExportReauthentication _reauthentication;
  final Set<String> _categories = {'ACCOUNT', 'LEGAL'};
  String _mediaQuality = 'NONE';
  _DateChoice _dateChoice = _DateChoice.allTime;
  DateTimeRange? _customRange;
  List<DataExportRequestModel> _requests = const [];
  bool _exportsExpanded = true;
  DataExportCapabilities? _capabilities;
  DataExportScope _scope = DataExportScope.all;
  final Set<String> _venueIds = {};
  Timer? _pollTimer;
  bool _loading = true;
  bool _loadError = false;
  bool _loadOffline = false;
  bool _submitting = false;
  String? _busyId;

  List<DataExportRequestModel> get _visibleRequests => _requests
      .where((request) => request.status != DataExportStatus.expired)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DataExportRepository();
    _reauthentication = widget.reauthentication ?? DataExportReauthentication();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quietly = false}) async {
    if (!quietly && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repository.list(),
        _repository.capabilities(),
      ]);
      final requests = results[0] as List<DataExportRequestModel>;
      final capabilities = results[1] as DataExportCapabilities;
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _capabilities = capabilities;
        if (!capabilities.availableScopes.contains(_scope)) {
          _scope = capabilities.defaultScope;
          _venueIds.clear();
        }
        _applyScopeDefaults();
        _loading = false;
        _loadError = false;
      });
      _syncPolling();
    } catch (error) {
      if (!mounted) return;
      final offline = isOfflineError(error);
      setState(() {
        _loading = false;
        // Only take over the whole screen when there is nothing to show yet.
        if (_capabilities == null) {
          _loadError = true;
          _loadOffline = offline;
        }
      });
      // If we already have content, a failed background refresh shouldn't nag.
      if (_capabilities != null && !quietly) _showRequestError(error);
    }
  }

  void _syncPolling() {
    final needsPolling = _requests.any((request) => request.isActive);
    if (needsPolling && _pollTimer == null) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _load(quietly: true),
      );
    } else if (!needsPolling) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<bool> _requireRecentAuthentication() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (_) => _ReauthenticationSheet(service: _reauthentication),
    );
    return result == true;
  }

  Future<void> _create() async {
    final activeRequest = _requests.cast<DataExportRequestModel?>().firstWhere(
      (item) => item?.isActive == true,
      orElse: () => null,
    );
    if (_submitting || activeRequest != null) {
      _showInfo(_activeExportMessage(activeRequest?.status));
      return;
    }
    if (_scope == DataExportScope.venue && _venueIds.isEmpty) {
      _showError('Select at least one venue to export.');
      return;
    }
    if (_categories.contains('LOCATION_HISTORY')) {
      final confirmed = await _confirmLocationExport();
      if (!confirmed || !mounted) return;
      if (!await _requireRecentAuthentication() || !mounted) return;
    }

    final range = _resolvedDateRange();
    setState(() => _submitting = true);
    try {
      final created = await _repository.create(
        categories: _categories,
        scope: _scope,
        venueIds: _venueIds,
        mediaQuality: _mediaQuality,
        dateFrom: range?.start,
        dateTo: range?.end,
      );
      if (!mounted) return;
      setState(() {
        _requests = [
          created,
          ..._requests.where((request) => request.id != created.id),
        ];
      });
      _syncPolling();
    } catch (error) {
      if (mounted) {
        if (error is ApiException &&
            error.data['errorCode']?.toString() ==
                'DATA_EXPORT_ALREADY_ACTIVE') {
          _showInfo(_friendlyError(error));
          await _load(quietly: true);
        } else {
          _showRequestError(error);
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _applyScopeDefaults() {
    if (_scope == DataExportScope.venue) {
      _categories
        ..removeAll({
          'SOCIAL',
          'MESSAGES',
          'LOCATION_HISTORY',
          'EVENTS',
          'PAYMENTS',
        })
        ..addAll({'ACCOUNT', 'LEGAL', 'VENUES'});
      if (_venueIds.isEmpty && _capabilities?.venues.length == 1) {
        _venueIds.add(_capabilities!.venues.single.id);
      }
    } else if (_scope == DataExportScope.personal) {
      _categories
        ..remove('VENUES')
        ..addAll({'ACCOUNT', 'LEGAL'});
      _venueIds.clear();
    } else {
      _categories.addAll({'ACCOUNT', 'LEGAL'});
      _venueIds.clear();
    }
  }

  void _selectScope(DataExportScope scope) {
    setState(() {
      _scope = scope;
      _venueIds.clear();
      _applyScopeDefaults();
    });
  }

  Future<void> _cancel(DataExportRequestModel request) async {
    final ready = request.status == DataExportStatus.ready;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          ready ? 'Delete this export archive?' : 'Cancel this export request?',
        ),
        content: Text(
          ready
              ? 'The prepared ZIP archive will be permanently removed and can no longer be downloaded. Your KMSTRY account data is not deleted.'
              : 'The request will stop and any partially prepared archive will be removed. Your KMSTRY account data is not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep export'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ready ? 'Delete archive' : 'Cancel export'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runFor(request.id, () => _repository.cancel(request.id));
  }

  Future<void> _retry(DataExportRequestModel request) async {
    if (request.includesLocation &&
        (!await _requireRecentAuthentication() || !mounted)) {
      return;
    }
    await _runFor(request.id, () => _repository.retry(request.id));
  }

  Future<void> _runFor(String id, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() => _busyId = id);
    try {
      await action();
      await _load(quietly: true);
    } catch (error) {
      if (mounted) _showRequestError(error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _saveDownload(DataExportRequestModel request) async {
    if (_busyId != null) return;
    setState(() => _busyId = request.id);
    File? temporaryFile;
    try {
      temporaryFile = await _prepareDownload(request);
      if (temporaryFile == null || !mounted) return;
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save your KMSTRY data export',
        fileName: _exportFileName(request),
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: await temporaryFile.readAsBytes(),
      );
      if (savedPath == null || !mounted) return;
      _showSuccess('Downloaded. Your export was saved successfully.');
      await _load(quietly: true);
    } catch (error) {
      if (mounted) _showRequestError(error);
    } finally {
      await _deleteTemporaryFile(temporaryFile);
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _shareDownload(DataExportRequestModel request) async {
    if (_busyId != null) return;
    setState(() => _busyId = request.id);
    File? temporaryFile;
    try {
      temporaryFile = await _prepareDownload(request);
      if (temporaryFile == null || !mounted) return;
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'KMSTRY data export',
          text: 'Your private KMSTRY data export. Store it securely.',
          files: [XFile(temporaryFile.path, mimeType: 'application/zip')],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted && result.status == ShareResultStatus.success) {
        _showSuccess('Export shared successfully.');
      }
      await _load(quietly: true);
    } catch (error) {
      if (mounted) _showRequestError(error);
    } finally {
      await _deleteTemporaryFile(temporaryFile);
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<File?> _prepareDownload(DataExportRequestModel request) async {
    if (!await _requireRecentAuthentication() || !mounted) {
      return null;
    }
    final authorization = await _repository.createDownload(request.id);
    final directory = await getTemporaryDirectory();
    final temporaryFile = File(
      '${directory.path}/kmstry-export-${request.id}.zip',
    );
    await Dio().download(
      authorization.url.toString(),
      temporaryFile.path,
      options: Options(
        followRedirects: false,
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 15),
      ),
    );
    final length = await temporaryFile.length();
    if (length != authorization.fileSizeBytes) {
      throw Exception('Downloaded export size did not match');
    }
    final digest = await sha256.bind(temporaryFile.openRead()).first;
    if (digest.toString() != authorization.checksumSha256) {
      throw Exception('Downloaded export integrity check failed');
    }
    return temporaryFile;
  }

  Future<void> _deleteTemporaryFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  String _exportFileName(DataExportRequestModel request) {
    final date = request.requestedAt.toLocal();
    final stamp =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return 'kmstry-${request.scope.apiValue.toLowerCase()}-export-$stamp.zip';
  }

  DateTimeRange? _resolvedDateRange() {
    final now = DateTime.now().subtract(const Duration(minutes: 1));
    return switch (_dateChoice) {
      _DateChoice.allTime => null,
      _DateChoice.lastMonth => DateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end: now,
      ),
      _DateChoice.lastYear => DateTimeRange(
        start: DateTime(now.year - 1, now.month, now.day),
        end: now,
      ),
      _DateChoice.custom =>
        _customRange == null
            ? null
            : DateTimeRange(
                start: _customRange!.start,
                end: _customRange!.end.isAfter(now) ? now : _customRange!.end,
              ),
    };
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateChoice = _DateChoice.custom;
      _customRange = DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
          999,
        ),
      );
    });
  }

  Future<bool> _confirmLocationExport() async {
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const _LocationExportConfirmSheet(),
        ) ??
        false;
  }

  void _showError(String message) {
    showBrandedNotice(
      context,
      title: 'Something went wrong',
      message: message,
      tone: BrandedNoticeTone.error,
    );
  }

  void _showRequestError(Object error) {
    if (_isRateLimited(error)) {
      showBrandedNotice(
        context,
        title: 'Please wait a moment',
        message:
            'Too many requests were made in a short time. Please wait a moment, then try again.',
        tone: BrandedNoticeTone.warning,
        icon: Icons.schedule_rounded,
      );
      return;
    }
    _showError(_friendlyError(error));
  }

  bool _isRateLimited(Object error) {
    if (error is ApiException && error.statusCode == 429) return true;
    final message = error.toString().toLowerCase();
    return message.contains('too many requests') ||
        message.contains('rate limit');
  }

  void _showInfo(
    String message, {
    String title = 'Export update',
    IconData icon = Icons.info_outline_rounded,
  }) {
    showBrandedNotice(
      context,
      title: title,
      message: message,
      tone: BrandedNoticeTone.info,
      icon: icon,
    );
  }

  void _showSuccess(String message) {
    showBrandedNotice(
      context,
      title: 'Export ready',
      message: message,
      tone: BrandedNoticeTone.success,
      icon: Icons.check_circle_outline_rounded,
    );
  }

  String _activeExportMessage(DataExportStatus? status) {
    final state = status == DataExportStatus.processing
        ? 'being prepared'
        : 'queued';
    return 'Your current export is $state. You can create another as soon as it is ready, cancelled, or fails. Status refreshes every 15 seconds.';
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      final code = error.data['errorCode']?.toString();
      final nextAllowedAt = DateTime.tryParse(
        error.data['nextAllowedAt']?.toString() ?? '',
      )?.toLocal();
      final retryMessage = nextAllowedAt == null
          ? 'Please wait before creating another data export.'
          : 'You can create another export at ${_formatTime(nextAllowedAt)}.';
      return switch (code) {
        'DATA_EXPORT_ALREADY_ACTIVE' => _activeExportMessage(
          DataExportStatus.parse(error.data['activeStatus']),
        ),
        'DATA_EXPORT_COOLDOWN' => retryMessage,
        'DATA_EXPORT_DAILY_LIMIT' =>
          'You reached today\'s export limit. $retryMessage',
        'DATA_EXPORT_REAUTHENTICATION_REQUIRED' =>
          'Please verify your identity again to continue.',
        'DATA_EXPORT_EXPIRED' =>
          'This archive has expired. Create a new export.',
        'DATA_EXPORT_NOT_READY_FOR_DOWNLOAD' =>
          'This export is not ready to download.',
        _ => error.toString(),
      };
    }
    return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark ? AppColors.darkBg : const Color(0xFFF7FAFD);
    final activeRequest = _requests.cast<DataExportRequestModel?>().firstWhere(
      (item) => item?.isActive == true,
      orElse: () => null,
    );
    final visibleRequests = _visibleRequests;
    final hasExpiredRequests = visibleRequests.length != _requests.length;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Download your data',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
          ? ConnectionErrorView(offline: _loadOffline, onRetry: () => _load())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : const Color(0xFFEEF7FD),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? AppColors.blueDark.withValues(alpha: 0.22)
                            : AppColors.blue.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.blue, AppColors.brand],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your information, your copy',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Choose what to include. We’ll prepare a private ZIP with portable JSON files and a simple README guide.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_capabilities?.requiresScopeSelection == true) ...[
                    _sectionTitle('Choose export', icon: Icons.tune_rounded),
                    _panel(
                      Column(
                        children: _capabilities!.availableScopes
                            .map(
                              (scope) => ListTile(
                                onTap: () => _selectScope(scope),
                                tileColor: scope == _scope
                                    ? colors.primary.withValues(alpha: 0.08)
                                    : Colors.transparent,
                                leading: Icon(
                                  _scopeIcon(scope),
                                  color: scope == _scope
                                      ? colors.primary
                                      : colors.onSurface.withValues(alpha: 0.7),
                                ),
                                title: Text(_scopeTitle(scope)),
                                subtitle: Text(_scopeSubtitle(scope)),
                                trailing: Icon(
                                  scope == _scope
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    _scopeSummary(),
                    const SizedBox(height: 20),
                  ],
                  if (_scope == DataExportScope.venue &&
                      (_capabilities?.venues.isNotEmpty ?? false)) ...[
                    _sectionTitle(
                      'Choose venue',
                      icon: Icons.storefront_outlined,
                    ),
                    _panel(
                      Column(
                        children: _capabilities!.venues
                            .map(
                              (venue) => CheckboxListTile(
                                value: _venueIds.contains(venue.id),
                                onChanged: (selected) => setState(() {
                                  if (selected == true) {
                                    _venueIds.add(venue.id);
                                  } else {
                                    _venueIds.remove(venue.id);
                                  }
                                }),
                                title: Text(venue.name),
                                subtitle: Text(
                                  '${venue.role.toLowerCase()} · ${venue.status.toLowerCase()}',
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  _sectionTitle(
                    'Choose information',
                    icon: Icons.fact_check_outlined,
                  ),
                  _panel(
                    Column(
                      children: _visibleCategoryOptions
                          .map(_categoryTile)
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Date range', icon: Icons.event_outlined),
                  _panel(
                    Column(
                      children: [
                        for (final choice in _DateChoice.values)
                          ListTile(
                            title: Text(choice.label),
                            subtitle:
                                choice == _DateChoice.custom &&
                                    _customRange != null
                                ? Text(_rangeLabel(_customRange!))
                                : null,
                            trailing: Icon(
                              _dateChoice == choice
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: _dateChoice == choice
                                  ? colors.primary
                                  : colors.onSurface.withValues(alpha: 0.5),
                            ),
                            onTap: () async {
                              if (choice == _DateChoice.custom) {
                                await _pickCustomRange();
                              } else {
                                setState(() => _dateChoice = choice);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Media', icon: Icons.perm_media_outlined),
                  _panel(
                    Column(
                      children: [
                        for (final o in const [
                          ['NONE', 'No media', 'Fastest, smallest archive'],
                          [
                            'ORIGINAL',
                            'Original quality',
                            'Full-resolution photos — largest',
                          ],
                        ])
                          ListTile(
                            onTap: () => setState(() => _mediaQuality = o[0]),
                            tileColor: _mediaQuality == o[0]
                                ? colors.primary.withValues(alpha: 0.08)
                                : Colors.transparent,
                            leading: Icon(
                              o[0] == 'NONE'
                                  ? Icons.block_rounded
                                  : Icons.photo_library_outlined,
                              color: _mediaQuality == o[0]
                                  ? colors.primary
                                  : colors.onSurface.withValues(alpha: 0.7),
                            ),
                            title: Text(o[1]),
                            subtitle: Text(o[2]),
                            trailing: Icon(
                              _mediaQuality == o[0]
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: _mediaQuality == o[0]
                                  ? colors.primary
                                  : colors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Keep this archive secure. It remains available for 4 days; exports containing precise location history expire after 48 hours.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurface.withValues(alpha: 0.72),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (activeRequest != null) ...[
                    _activeExportCard(activeRequest),
                    const SizedBox(height: 14),
                  ],
                  FilledButton.icon(
                    onPressed: _submitting || activeRequest != null
                        ? null
                        : _create,
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? AppColors.blueDark
                          : AppColors.blue,
                      foregroundColor: const Color(0xFF06101A),
                      minimumSize: const Size.fromHeight(54),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            activeRequest?.status == DataExportStatus.processing
                                ? Icons.sync_rounded
                                : activeRequest != null
                                ? Icons.schedule_rounded
                                : Icons.archive_outlined,
                          ),
                    label: Text(
                      _submitting
                          ? 'Starting…'
                          : activeRequest?.status == DataExportStatus.processing
                          ? 'Preparing export'
                          : activeRequest != null
                          ? 'Export queued'
                          : 'Create export',
                    ),
                  ),
                  const SizedBox(height: 28),
                  InkWell(
                    onTap: () =>
                        setState(() => _exportsExpanded = !_exportsExpanded),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _sectionTitle(
                            'Your exports',
                            icon: Icons.folder_zip_outlined,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _load(),
                          tooltip: 'Refresh',
                          icon: const Icon(Icons.refresh),
                        ),
                        AnimatedRotation(
                          turns: _exportsExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: colors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                  if (_exportsExpanded) ...[
                    const SizedBox(height: 6),
                    if (visibleRequests.isEmpty)
                      _panel(
                        const Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'You do not have any active or downloadable exports.',
                          ),
                        ),
                      )
                    else
                      ...visibleRequests.map(_requestCard),
                    if (hasExpiredRequests) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Expired archives are no longer available for download.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.58),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 2),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _panel(Widget child) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? AppColors.darkSurface
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xFFE6EEF4),
        ),
      ),
      child: child,
    );
  }

  Widget _activeExportCard(DataExportRequestModel request) {
    final processing = request.status == DataExportStatus.processing;
    return BrandedNoticeCard(
      title: processing ? 'Preparing your export' : 'Export queued',
      message: processing
          ? 'Your private archive is being prepared. You can create another export when this one is ready.'
          : 'Your request is waiting securely. Status refreshes automatically every 15 seconds.',
      tone: BrandedNoticeTone.info,
      icon: processing ? Icons.sync_rounded : Icons.schedule_rounded,
    );
  }

  Widget _categoryTile(_CategoryOption option) {
    final mandatory =
        option.id == 'ACCOUNT' ||
        option.id == 'LEGAL' ||
        (_scope == DataExportScope.venue && option.id == 'VENUES');
    return CheckboxListTile(
      value: _categories.contains(option.id),
      onChanged: mandatory
          ? null
          : (selected) => setState(() {
              if (selected == true) {
                _categories.add(option.id);
              } else {
                _categories.remove(option.id);
              }
            }),
      title: Text(option.title),
      subtitle: Text(option.subtitle),
      secondary: Icon(
        option.icon,
        color: Theme.of(context).colorScheme.primary,
      ),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  List<_CategoryOption> get _visibleCategoryOptions => _categoryOptions
      .where((option) {
        if (_scope == DataExportScope.personal) return option.id != 'VENUES';
        if (_scope == DataExportScope.venue) {
          return const {
            'ACCOUNT',
            'LEGAL',
            'AUTHENTICATION',
            'ACTIVITY',
            'NOTIFICATIONS',
            'VENUES',
          }.contains(option.id);
        }
        return true;
      })
      .toList(growable: false);

  Widget _scopeSummary() {
    final colors = Theme.of(context).colorScheme;
    return _panel(
      ListTile(
        leading: Icon(_scopeIcon(_scope), color: colors.primary),
        title: Text(_scopeTitle(_scope)),
        subtitle: Text(_scopeSubtitle(_scope)),
      ),
    );
  }

  /// One "Label ················ value" row for an export card — muted label on
  /// the left, readable value pushed to the right so text never hugs one edge.
  Widget _metaRow(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurface.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _requestScopeLabel(DataExportRequestModel request) {
    if (request.scope != DataExportScope.venue || request.venueIds.isEmpty) {
      return _scopeTitle(request.scope);
    }
    final names = request.venueIds.map((id) {
      for (final venue
          in _capabilities?.venues ?? const <DataExportVenueCapability>[]) {
        if (venue.id == id) return venue.name;
      }
      return 'Venue';
    }).toSet();
    return names.join(', ');
  }

  Widget _requestCard(DataExportRequestModel request) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final busy = _busyId == request.id;
    final ready = request.status == DataExportStatus.ready;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _statusIcon(request.status),
                      color: colors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusLabel(request.status),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (ready) ...[
                    IconButton.filled(
                      onPressed: () => _saveDownload(request),
                      tooltip: 'Download',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 38,
                        height: 38,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? AppColors.blueDark
                            : AppColors.blue,
                        foregroundColor: const Color(0xFF06101A),
                      ),
                      icon: const Icon(Icons.download_outlined, size: 19),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      onPressed: () => _shareDownload(request),
                      tooltip: 'Share',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 38,
                        height: 38,
                      ),
                      style: IconButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(
                          color: colors.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      icon: const Icon(Icons.ios_share_outlined, size: 19),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: colors.onSurface.withValues(alpha: 0.08),
              ),
              const SizedBox(height: 12),
              _metaRow('Requested', _dateTimeLabel(request.requestedAt)),
              _metaRow('Scope', _requestScopeLabel(request)),
              if (request.expiresAt != null)
                _metaRow('Available until', _dateTimeLabel(request.expiresAt!)),
              if (request.fileSizeBytes != null)
                _metaRow('Size', _fileSize(request.fileSizeBytes!)),
              if (request.canRetry || request.canCancel) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (request.canRetry)
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => _retry(request),
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('Retry'),
                      ),
                    if (request.canRetry && request.canCancel)
                      const SizedBox(width: 8),
                    if (request.canCancel)
                      TextButton(
                        onPressed: busy ? null : () => _cancel(request),
                        child: Text(ready ? 'Delete archive' : 'Cancel export'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _scopeTitle(DataExportScope scope) => switch (scope) {
  DataExportScope.all => 'All my KMSTRY data',
  DataExportScope.personal => 'Personal profile data',
  DataExportScope.venue => 'Venue-related data',
};

String _scopeSubtitle(DataExportScope scope) => switch (scope) {
  DataExportScope.all =>
    'Shared account, personal profile and your venue relationships',
  DataExportScope.personal =>
    'Your profile, activity, social data and personal interactions',
  DataExportScope.venue =>
    'Your membership, role, verification and venue-created content',
};

IconData _scopeIcon(DataExportScope scope) => switch (scope) {
  DataExportScope.all => Icons.archive_outlined,
  DataExportScope.personal => Icons.person_outline,
  DataExportScope.venue => Icons.storefront_outlined,
};

class _ReauthenticationSheet extends StatefulWidget {
  const _ReauthenticationSheet({required this.service});
  final DataExportReauthentication service;

  @override
  State<_ReauthenticationSheet> createState() => _ReauthenticationSheetState();
}

class _ReauthenticationSheetState extends State<_ReauthenticationSheet> {
  final _password = TextEditingController();
  String? _email;
  bool _hasPassword = true;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadAccount() async {
    try {
      final auth = AuthRepository();
      final me = await auth.getMe();
      if (!mounted) return;
      setState(() {
        _email = me['email']?.toString();
        _hasPassword = auth.hasLocalPasswordProvider(me);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final mutedColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.blueDark : AppColors.blue;
    final fieldFill = isDark
        ? const Color(0xFF0F1C30)
        : const Color(0xFFF7FAFD);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : const Color(0xFFDCE6EF);
    final socialButtonStyle = OutlinedButton.styleFrom(
      backgroundColor: fieldFill,
      foregroundColor: textColor,
      side: BorderSide(color: borderColor),
    );

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: borderColor),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            10,
            22,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: mutedColor.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.blue, AppColors.brand],
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verify it’s you',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'One quick security check',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      style: IconButton.styleFrom(
                        backgroundColor: fieldFill,
                        foregroundColor: mutedColor,
                      ),
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.1 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_outlined, size: 20, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your export may contain private and sensitive information. Confirm your identity before creating a location export or downloading any archive.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: mutedColor,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (_hasPassword && _email != null) ...[
                    Text(
                      'Signed in as $_email',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: Icon(
                          Icons.lock_outline_rounded,
                          color: mutedColor,
                        ),
                        filled: true,
                        fillColor: fieldFill,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: accent, width: 1.3),
                        ),
                      ),
                      onSubmitted: (_) => _passwordReauthenticate(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _passwordReauthenticate,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: const Color(0xFF06101A),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify with password'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Divider(color: borderColor)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or continue with',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: mutedColor,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: borderColor)),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(widget.service.withGoogle),
                    style: socialButtonStyle,
                    icon: const Icon(Icons.g_mobiledata_rounded),
                    label: const Text('Google'),
                  ),
                  if (Platform.isIOS || Platform.isMacOS) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.service.withApple),
                      style: socialButtonStyle,
                      icon: const Icon(Icons.apple),
                      label: const Text('Apple'),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _passwordReauthenticate() {
    final email = _email;
    if (email == null || _password.text.isEmpty) return;
    _run(
      () => widget.service.withPassword(email: email, password: _password.text),
    );
  }
}

/// Premium confirmation sheet shown before including precise location history
/// in an export. Replaces the stock Material AlertDialog so the "sensitive
/// data" step matches the app's branded design language.
class _LocationExportConfirmSheet extends StatelessWidget {
  const _LocationExportConfirmSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final mutedColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.blueDark : AppColors.blue;
    final fieldFill = isDark
        ? const Color(0xFF0F1C30)
        : const Color(0xFFF7FAFD);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : const Color(0xFFDCE6EF);

    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: accent),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: borderColor),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: mutedColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.blue, AppColors.brand],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Include location history?',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Precise places and movements',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    style: IconButton.styleFrom(
                      backgroundColor: fieldFill,
                      foregroundColor: mutedColor,
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.1 : 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    point(
                      Icons.visibility_outlined,
                      'This archive may reveal sensitive places and movement patterns.',
                    ),
                    point(
                      Icons.schedule_rounded,
                      'The download link expires 48 hours after it is ready.',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 19,
                            color: accent,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              'You’ll be asked to verify your identity before it’s created.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedColor,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF06101A),
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Continue securely'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: mutedColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DateChoice { allTime, lastMonth, lastYear, custom }

extension on _DateChoice {
  String get label => switch (this) {
    _DateChoice.allTime => 'All time',
    _DateChoice.lastMonth => 'Last 30 days',
    _DateChoice.lastYear => 'Last year',
    _DateChoice.custom => 'Custom range',
  };
}

class _CategoryOption {
  const _CategoryOption(this.id, this.title, this.subtitle, this.icon);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

const _categoryOptions = [
  _CategoryOption(
    'ACCOUNT',
    'Account and profile',
    'Always included',
    Icons.person_outline,
  ),
  _CategoryOption(
    'LEGAL',
    'Legal consents',
    'Always included',
    Icons.gavel_outlined,
  ),
  _CategoryOption(
    'AUTHENTICATION',
    'Sign-in history',
    'Safe account security history',
    Icons.lock_outline,
  ),
  _CategoryOption(
    'ACTIVITY',
    'Activity',
    'Check-ins and stories you created',
    Icons.auto_awesome_outlined,
  ),
  _CategoryOption(
    'SOCIAL',
    'Social connections',
    'Matches, follows and blocks you created',
    Icons.people_outline,
  ),
  _CategoryOption(
    'MESSAGES',
    'Messages',
    'Messages and reactions you sent',
    Icons.chat_bubble_outline,
  ),
  _CategoryOption(
    'NOTIFICATIONS',
    'Notifications',
    'Notifications associated with your account',
    Icons.notifications_outlined,
  ),
  _CategoryOption(
    'VENUES',
    'Venues',
    'Your venue memberships and roles',
    Icons.storefront_outlined,
  ),
  _CategoryOption(
    'EVENTS',
    'Events',
    'Your event activity and tickets',
    Icons.event_outlined,
  ),
  _CategoryOption(
    'PAYMENTS',
    'Payments',
    'Safe subscription and purchase history',
    Icons.receipt_long_outlined,
  ),
  _CategoryOption(
    'LOCATION_HISTORY',
    'Precise location history',
    'Sensitive — off by default and expires sooner',
    Icons.location_on_outlined,
  ),
];

String _statusLabel(DataExportStatus status) => switch (status) {
  DataExportStatus.pending => 'Queued',
  DataExportStatus.processing => 'Preparing securely',
  DataExportStatus.ready => 'Ready to download',
  DataExportStatus.failed => 'Export could not be prepared',
  DataExportStatus.expired => 'Expired',
  DataExportStatus.cancelled => 'Cancelled',
};

IconData _statusIcon(DataExportStatus status) => switch (status) {
  DataExportStatus.pending => Icons.schedule,
  DataExportStatus.processing => Icons.sync,
  DataExportStatus.ready => Icons.check_circle_outline,
  DataExportStatus.failed => Icons.error_outline,
  DataExportStatus.expired => Icons.timer_off_outlined,
  DataExportStatus.cancelled => Icons.cancel_outlined,
};

String _dateTimeLabel(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

String _rangeLabel(DateTimeRange range) =>
    '${_dateTimeLabel(range.start)} – ${_dateTimeLabel(range.end)}';

String _fileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes bytes';
}
