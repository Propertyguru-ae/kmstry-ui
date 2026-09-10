import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/notification_permission_page.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/force_dark.dart';

enum _Step { search, contact, documents, review }

/// Venue claim wizard — 4 adım:
/// 1. Venue seç
/// 2. İletişim bilgileri (ad soyad, telefon)
/// 3. Belgeler (ticari lisans, sahiplik videosu)
/// 4. Özet & Gönder
///
/// Her adım tamamlanınca server-side draft kaydedilir.
/// Sayfa açılırken mevcut draft kontrol edilir ve varsa kaldığı adımdan devam edilir.
class VenueContextOnboardingPage extends StatefulWidget {
  final bool fromAppShell;
  final VoidCallback? onCancel;
  const VenueContextOnboardingPage({
    super.key,
    this.fromAppShell = false,
    this.onCancel,
  });

  @override
  State<VenueContextOnboardingPage> createState() =>
      _VenueContextOnboardingPageState();
}

class _VenueContextOnboardingPageState
    extends State<VenueContextOnboardingPage> {
  final _repo = VenueRepository();

  // ── Adım ─────────────────────────────────────────────────────────────────
  _Step _step = _Step.search;

  // ── Step 1: Venue ara ─────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Venue> _results = [];
  Venue? _selectedVenue;
  String? _dbVenueId; // ensureVenueDbId sonucu — draft ve claim için kullanılır
  bool _searching = false;

  // ── Step 2: İletişim ─────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  // Varsayılan telefon kodu UAE (KMSTRY birincil pazarı). Kullanıcı isterse
  // dropdown'dan değiştirebilir.
  _CountryCode _selectedCountry = _countryCodes.firstWhere(
    (c) => c.code == 'AE',
  );

  void _clearErrorOnType() {
    if (_error != null) setState(() => _error = null);
  }

  // ── Step 3: Belgeler ─────────────────────────────────────────────────────
  String? _tradeLicenceUrl;
  String? _ownerVideoUrl;
  bool _uploadingLicence = false;
  bool _uploadingVideo = false;

  // ── Genel ─────────────────────────────────────────────────────────────────
  bool _loadingDraft = true;
  bool _draftInitFailed = false;
  bool _savingDraft = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _nameCtrl.addListener(_clearErrorOnType);
    _phoneCtrl.addListener(_clearErrorOnType);
    _loadDraft();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Draft yönetimi ────────────────────────────────────────────────────────

  Future<void> _loadDraft() async {
    setState(() => _loadingDraft = true);
    try {
      final draft = await _repo.getClaimDraft();
      if (!mounted) return;
      if (draft != null) {
        debugPrint('[VenueWizard] draft loaded step=${draft['current_step']}');
        _applyDraft(draft);
      } else {
        // Draft yok → hemen boş draft oluştur.
        // hasClaimDraft=true olması için gerekli — restart'ta personal'a düşmeyi önler.
        await _repo.upsertClaimDraft(currentStep: 1);
      }
      // İsim alanı henüz boşsa kullanıcının profil ad-soyadıyla önceden doldur.
      // Kullanıcı Step 2'de dilerse düzenleyebilir.
      if (_nameCtrl.text.trim().isEmpty) {
        await _prefillOwnerName();
      }
    } catch (e) {
      debugPrint('[VenueClaimFlow] draft init failed: $e');
      if (mounted) setState(() => _draftInitFailed = true);
    } finally {
      if (mounted) setState(() => _loadingDraft = false);
    }
  }

  /// Owner adını mevcut kullanıcının profilinden doldurur (boşsa).
  Future<void> _prefillOwnerName() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      final fullName = (me['fullName'] ?? me['full_name'])?.toString().trim();
      if (fullName != null &&
          fullName.isNotEmpty &&
          _nameCtrl.text.trim().isEmpty) {
        setState(() => _nameCtrl.text = fullName);
      }
    } catch (e) {
      debugPrint('[VenueWizard] owner name prefill failed: $e');
    }
  }

  void _applyDraft(Map<String, dynamic> draft) {
    final step = draft['current_step'] as int? ?? 1;
    final venueData = draft['venue'] as Map<String, dynamic>?;

    if (venueData != null) {
      _selectedVenue = Venue.fromJson(venueData);
      _searchCtrl.text = _selectedVenue!.name;
      // Draft'ta venue varsa DB'de zaten kayıtlı — ID'si venue.id (UUID)
      _dbVenueId = venueData['id']?.toString();
    }
    _nameCtrl.text = draft['owner_full_name']?.toString() ?? '';
    _phoneCtrl.text = draft['owner_phone']?.toString() ?? '';
    _tradeLicenceUrl = draft['trade_licence_url']?.toString();
    _ownerVideoUrl = draft['owner_video_url']?.toString();

    _step = switch (step) {
      2 => _Step.contact,
      3 => _Step.documents,
      4 => _Step.review,
      _ => _Step.search,
    };
  }

  Future<void> _saveDraft({required int stepNumber}) async {
    setState(() => _savingDraft = true);
    try {
      debugPrint(
        '[VenueWizard] saving draft step=$stepNumber venueId=${_selectedVenue?.id}',
      );
      await _repo.upsertClaimDraft(
        venueId: _dbVenueId,
        ownerFullName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : null,
        ownerPhone: _phoneCtrl.text.trim().isNotEmpty ? _fullPhone : null,
        tradeLicenceUrl: _tradeLicenceUrl,
        ownerVideoUrl: _ownerVideoUrl,
        currentStep: stepNumber,
      );
      debugPrint('[VenueWizard] draft saved ok step=$stepNumber');
    } catch (e) {
      debugPrint('[VenueWizard] draft save FAILED (step $stepNumber): $e');
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  // ── Step 1: Venue arama ───────────────────────────────────────────────────

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (_selectedVenue != null && q != _selectedVenue!.name) {
      setState(() => _selectedVenue = null);
    }
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final venues = await _repo.searchVenues(query: q);
      if (!mounted) return;
      setState(() => _results = venues);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Search failed. Please try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onVenueSelected(Venue venue) {
    setState(() {
      _selectedVenue = venue;
      // Venue zaten DB'de ise (ör. daha önce claim edilip bırakılmış) id'si DB
      // UUID'sidir → doğrudan kullan; resolve-from-place'e (Google place_id
      // bekler) UUID göndermek "could not submit" hatasına yol açıyordu.
      // Google-only place ise resolve gerekir → null bırak.
      _dbVenueId = venue.isInDb ? venue.id : null;
      _searchCtrl.text = venue.name;
      _results = [];
      _error = null;
    });
  }

  Future<void> _onSearchContinue() async {
    if (_selectedVenue == null) {
      setState(() => _error = 'Please select a venue to continue.');
      return;
    }
    setState(() {
      _error = null;
      _searching = true;
    });
    try {
      // Zaten DB'de olan venue için resolve'a gerek yok (id = DB UUID).
      // Google-only place ise placeId ile resolve et (id fallback).
      _dbVenueId ??= _selectedVenue!.isInDb
          ? _selectedVenue!.id
          : await _repo.ensureVenueDbId(
              _selectedVenue!.placeId ?? _selectedVenue!.id,
            );
    } catch (_) {
      // Başarısız olsa bile devam et; submit'te tekrar denenecek
    } finally {
      if (mounted) setState(() => _searching = false);
    }
    await _saveDraft(stepNumber: 1);
    if (mounted) setState(() => _step = _Step.contact);
  }

  // ── Step 2: İletişim ──────────────────────────────────────────────────────

  String get _fullPhone {
    final raw = _phoneCtrl.text.trim();
    if (raw.startsWith('+')) return raw; // kullanıcı zaten tam numara girmiş
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return '${_selectedCountry.dial}$digits';
  }

  Future<void> _onContactContinue() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'Please enter your phone number.');
      return;
    }
    setState(() => _error = null);
    await _saveDraft(stepNumber: 2);
    if (mounted) setState(() => _step = _Step.documents);
  }

  // ── Step 3: Belgeler ──────────────────────────────────────────────────────

  Future<void> _pickTradeLicence() async {
    setState(() {
      _uploadingLicence = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final url = await _uploadFile(File(path), 'licence');
      if (!mounted) return;
      setState(() => _tradeLicenceUrl = url);
    } catch (e) {
      debugPrint('[VenueWizard] trade licence upload error: $e');
      if (!mounted) return;
      setState(() => _error = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingLicence = false);
    }
  }

  Future<void> _pickOwnerVideo() async {
    setState(() {
      _uploadingVideo = true;
      _error = null;
    });
    try {
      final source = await _showVideoSourceSheet();
      if (source == null) return;
      final picker = ImagePicker();
      final picked = source == ImageSource.camera
          ? await picker.pickVideo(source: ImageSource.camera)
          : await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      final url = await _uploadFile(File(picked.path), 'video');
      if (!mounted) return;
      setState(() {
        _ownerVideoUrl = url;
        _error = null;
      });
    } catch (e) {
      debugPrint('[VenueWizard] video upload error: $e');
      if (!mounted) return;
      setState(() => _error = 'Failed to upload video: $e');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<ImageSource?> _showVideoSourceSheet() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Record a video'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Dosyayı POST /venues/claim-draft/upload?type=licence|video ile yükler.
  /// Başarıda DigitalOcean Spaces URL'si döner; hata durumunda exception fırlatır.
  Future<String> _uploadFile(File file, String type) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse(
      '${AppConfig.baseUrl}/venues/claim-draft/upload?type=$type',
    );
    debugPrint('[VenueWizard] uploading to $uri');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(await AppRequestHeaders.build(accessToken: token))
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await sendMultipartRequest(request);
    final body = await streamed.stream.bytesToString();
    debugPrint('[VenueWizard] upload response status=${streamed.statusCode}');

    if (streamed.statusCode >= 400) {
      Map<String, dynamic> data = {};
      try {
        data = Map<String, dynamic>.from(jsonDecode(body) as Map);
      } catch (_) {}
      throw ApiException(statusCode: streamed.statusCode, data: data);
    }

    final decoded = Map<String, dynamic>.from(jsonDecode(body) as Map);
    final url = decoded['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception('Upload succeeded but no URL returned.');
    }
    return url;
  }

  Future<void> _onDocumentsContinue() async {
    if (_tradeLicenceUrl == null) {
      setState(() => _error = 'Please upload your trade licence.');
      return;
    }
    if (_ownerVideoUrl == null) {
      setState(() => _error = 'Please upload your ownership video.');
      return;
    }
    setState(() => _error = null);
    await _saveDraft(stepNumber: 3);
    if (mounted) setState(() => _step = _Step.review);
  }

  Future<void> _onDocumentsSkip() async {
    _tradeLicenceUrl = null;
    _ownerVideoUrl = null;
    await _saveDraft(stepNumber: 3);
    if (mounted)
      setState(() {
        _error = null;
        _step = _Step.review;
      });
  }

  // ── Step 4: Submit ────────────────────────────────────────────────────────

  Future<void> _submitClaim() async {
    final venue = _selectedVenue;
    if (venue == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final hasDocuments = _tradeLicenceUrl != null && _ownerVideoUrl != null;

    try {
      final dbVenueId =
          _dbVenueId ??
          (venue.isInDb
              ? venue.id
              : await _repo.ensureVenueDbId(venue.placeId ?? venue.id));
      await _repo.claimVenue(
        venueId: dbVenueId,
        ownerFullName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : null,
        ownerNote: [
          'Owner: ${_nameCtrl.text.trim()}',
          'Phone: ${_phoneCtrl.text.trim()}',
          if (hasDocuments) 'Trade licence uploaded.',
          if (_ownerVideoUrl != null) 'Ownership video uploaded.',
        ].join('\n'),
        tradeLicenceUrl: _tradeLicenceUrl,
        ownerVideoUrl: _ownerVideoUrl,
        hasDocuments: hasDocuments,
      );
      AuthRepository.invalidateMeCache();
      await AuthRepository().switchContext(
        lastActiveContext: 'VENUE',
        activeVenueId: dbVenueId,
      );
      await _repo.deleteClaimDraft();
      if (!mounted) return;
      _onClaimSuccess(hasDocuments: hasDocuments);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('already pending') ||
          msg.contains('already an active')) {
        await _repo.deleteClaimDraft();
        if (mounted) _onClaimSuccess(hasDocuments: hasDocuments);
        return;
      }
      setState(() {
        _error = 'Could not submit your claim. Please try again.';
        _submitting = false;
      });
    }
  }

  void _showCountryPicker(ColorScheme colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => _CountryPickerSheet(
        selected: _selectedCountry,
        colors: colors,
        onSelected: (c) {
          setState(() => _selectedCountry = c);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _onClaimSuccess({bool hasDocuments = true}) async {
    final notifDone = await SecureStorage.isNotificationOnboardingDone();
    if (!mounted) return;
    if (!notifDone) {
      // Personal ile aynı: yeni venue-signup → dark; add-venue → seçilen tema.
      final forceDark = !widget.fromAppShell && widget.onCancel == null;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) {
            final page = NotificationPermissionPage(
              onNext: () => Navigator.of(
                context,
              ).pushReplacementNamed(AuthRoutes.authGate),
            );
            return forceDark ? ForceDark(child: page) : page;
          },
        ),
      );
    } else {
      Navigator.of(context).pushReplacementNamed(AuthRoutes.authGate);
    }
  }

  // ── "Use a different account" ─────────────────────────────────────────────

  Future<void> _useDifferentAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use a different account?'),
        content: const Text(
          'You will be signed out. Your progress has been saved and you can continue later by signing in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AuthRepository().logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AuthRoutes.login);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  static const _darkBg = Color(0xFF06091A);
  static const _blue = AppColors.blue;
  static const _teal = Color(0xFF00D4C8);

  @override
  Widget build(BuildContext context) {
    // Personal ile aynı mantık: yeni venue-signup / ilk kurulum (paramsız) →
    // marka akışı, DAİMA dark. Login sonrası add-venue (fromAppShell veya
    // onCancel ile açılan) → kullanıcının seçtiği temayı izler.
    final forceDark = !widget.fromAppShell && widget.onCancel == null;
    final content = Builder(builder: _buildBody);
    return forceDark ? ForceDark(child: content) : content;
  }

  Widget _buildBody(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loadingDraft) {
      return Scaffold(
        backgroundColor: isDark ? _darkBg : Colors.white,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.blue),
        ),
      );
    }

    if (_draftInitFailed) {
      return Scaffold(
        backgroundColor: isDark ? _darkBg : Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0x1A3B6DEA),
                    border: Border.all(color: const Color(0x2E3B6DEA)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 30,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connection error',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not connect to the server. Please check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF4A6280) : Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _draftInitFailed = false;
                      _loadingDraft = true;
                    });
                    _loadDraft();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E4FC7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Try again',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: Stack(
        children: [
          // Ambient glows
          if (isDark) ...[
            Positioned(
              top: -70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 300,
                  height: 260,
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.4),
                      radius: 1.0,
                      colors: [Color(0x243B6DEA), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 60,
              right: -50,
              child: Container(
                width: 160,
                height: 160,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x128C46FF), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(isDark),
                _buildStepTabs(isDark),
                Expanded(
                  child: switch (_step) {
                    _Step.search => _buildSearchStep(colors, isDark),
                    _Step.contact => _buildContactStep(colors),
                    _Step.documents => _buildDocumentsStep(colors, isDark),
                    _Step.review => _buildReviewStep(colors, isDark),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_step != _Step.search ||
              widget.onCancel != null ||
              Navigator.of(context).canPop())
            GestureDetector(
              onTap: () {
                if (_step != _Step.search) {
                  setState(() {
                    _step = _Step.values[_step.index - 1];
                    _error = null;
                  });
                } else if (widget.onCancel != null) {
                  widget.onCancel!();
                } else {
                  // Opened via Navigator.push (e.g. from Manage Accounts) —
                  // pop back instead of forcing a sign-out.
                  Navigator.of(context).maybePop();
                }
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.1),
                  ),
                ),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 22,
                  color: isDark ? const Color(0xFF607090) : Colors.black54,
                ),
              ),
            )
          else
            const SizedBox(width: 38),
          GestureDetector(
            onTap: _useDifferentAccount,
            child: const Text(
              'Use a different account →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.blueDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTabs(bool isDark) {
    const labels = ['Venue', 'Contact', 'Documents', 'Review'];
    final current = _step.index;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1525) : const Color(0xFFF0F5FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF1A2A4A) : const Color(0xFFD4E0FF),
          ),
        ),
        child: Row(
          children: List.generate(4, (i) {
            final active = i == current;
            final done = i < current;
            Color numBg, numFg, labelFg;
            if (active) {
              numBg = const Color(0xFF1E4FC7);
              numFg = Colors.white;
              labelFg = AppColors.blueDark;
            } else if (done) {
              numBg = const Color(0x3300D4C8);
              numFg = _teal;
              labelFg = _teal;
            } else {
              numBg = isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05);
              numFg = isDark ? const Color(0xFF2E4560) : Colors.black38;
              labelFg = isDark ? const Color(0xFF2E4560) : Colors.black38;
            }
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: active
                      ? (isDark
                            ? const Color(0xFF0D1F45)
                            : const Color(0xFFEEF4FF))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: numBg,
                      ),
                      child: Center(
                        child: done
                            ? Icon(Icons.check_rounded, size: 11, color: numFg)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: numFg,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: labelFg,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Step 1: Venue Ara ─────────────────────────────────────────────────────

  Widget _buildSearchStep(ColorScheme colors, bool isDark) {
    final hasQuery = _searchCtrl.text.trim().isNotEmpty;
    final hasResults = _results.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 2,
                        decoration: BoxDecoration(
                          color: _blue,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'STEP 1 OF 4',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                          color: AppColors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Find your',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                      height: 1.12,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: AppColors.gradientDark,
                    ).createShader(b),
                    blendMode: BlendMode.srcIn,
                    child: const Text(
                      'venue.',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        height: 1.12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Search by venue name or city to get started.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: isDark ? const Color(0xFFB1B4BB) : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),

            // Search box
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F1C35)
                      : const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _searching
                        ? _blue
                        : (isDark
                              ? const Color(0xFF1A3060)
                              : const Color(0xFFD4E0FF)),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: _searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.blue,
                              ),
                            )
                          : const Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: AppColors.blue,
                            ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? const Color(0xFFEEF2FF)
                              : const Color(0xFF111827),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search venues...',
                          hintStyle: TextStyle(
                            color: isDark
                                ? const Color(0xFF2E4560)
                                : Colors.black26,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                        ),
                      ),
                    ),
                    if (hasQuery)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() {
                            _results = [];
                            _selectedVenue = null;
                          });
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(right: 14),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : Colors.black.withValues(alpha: 0.07),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: isDark
                                ? const Color(0xFF4A6280)
                                : Colors.black38,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),

            // Results list (shrinkWrap — no Expanded needed)
            if (hasResults && _selectedVenue == null)
              _buildResultsList(isDark)
            else if (!hasResults)
              _buildEmptyState(isDark, idle: !hasQuery || _searching),

            // Selected venue + continue
            if (_selectedVenue != null) _buildSelectedVenueBar(colors, isDark),

            // Can't find
            if (_selectedVenue == null) _buildCantFind(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(bool isDark) {
    // If a venue is selected, show results collapsed
    if (_selectedVenue != null) return const SizedBox.shrink();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final venue = _results[i];
        return GestureDetector(
          onTap: () => _onVenueSelected(venue),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1525) : const Color(0xFFF8FAFF),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF162040)
                    : const Color(0xFFD4E0FF),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A2A4A)
                        : const Color(0xFFEEF4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: venue.photoUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            venue.photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.store_mall_directory_outlined,
                              size: 18,
                              color: Color(0xFF4A6AAA),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.store_mall_directory_outlined,
                          size: 18,
                          color: Color(0xFF4A6AAA),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venue.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFFC8D8F0)
                              : const Color(0xFF111827),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (venue.address.isNotEmpty)
                        Text(
                          venue.address,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF3A5070)
                                : Colors.black45,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark ? const Color(0xFF2E4060) : Colors.black26,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark, {bool idle = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0x1A3B6DEA),
              border: Border.all(color: const Color(0x2E3B6DEA)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.store_mall_directory_outlined,
              size: 24,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            idle ? 'Find your venue' : 'No venues found',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? const Color.fromARGB(255, 79, 102, 130)
                  : Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            idle
                ? 'Type a venue name or city above.'
                : 'Try a different name or add it manually below.',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: isDark
                  ? Color.fromARGB(255, 147, 153, 167)
                  : Colors.black38,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedVenueBar(ColorScheme colors, bool isDark) {
    final venue = _selectedVenue!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1F45) : const Color(0xFFEEF4FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.blue),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A2A4A)
                        : const Color(0xFFD4E4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: venue.photoUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            venue.photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.store_mall_directory_outlined,
                              size: 18,
                              color: Color(0xFF4A6AAA),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.store_mall_directory_outlined,
                          size: 18,
                          color: Color(0xFF4A6AAA),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venue.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFC8D8F0)
                              : const Color(0xFF111827),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (venue.address.isNotEmpty)
                        Text(
                          venue.address,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5B6F8D),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.blue,
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _savingDraft ? null : _onSearchContinue,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF1E4FC7),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 26,
                      decoration: const BoxDecoration(
                        color: Color(0x12FFFFFF),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: _savingDraft
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCantFind(bool isDark) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x143B6DEA),
          border: Border.all(color: const Color(0x293B6DEA)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0x263B6DEA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 18,
                color: AppColors.blueDark,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Can't find your venue?",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7AAAFF),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Add it manually and we'll verify it",
                    style: TextStyle(fontSize: 11, color: Color(0xFF5B6F8D)),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.blue,
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: İletişim Bilgileri ────────────────────────────────────────────

  Widget _buildContactStep(ColorScheme colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final venue = _selectedVenue;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 2,
                      decoration: BoxDecoration(
                        color: _blue,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'STEP 2 OF 4',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Your contact',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                    height: 1.12,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                ShaderMask(
                  shaderCallback: (b) => LinearGradient(
                    colors: isDark
                        ? AppColors.gradientDark
                        : AppColors.gradientLight,
                  ).createShader(b),
                  blendMode: BlendMode.srcIn,
                  child: const Text(
                    'details.',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                      height: 1.12,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'These will be used to verify your ownership.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: isDark ? const Color(0xFFB1B4BB) : Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          // Venue chip
          if (venue != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.10),
                  border: Border.all(
                    color: AppColors.blue.withValues(alpha: 0.20),
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1540A0)
                            : const Color(0xFFDCEAFF),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        Icons.store_mall_directory_outlined,
                        size: 15,
                        color: isDark
                            ? const Color(0xFF90B8FF)
                            : AppColors.blueLight,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            venue.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFFAAC4FF)
                                  : const Color(0xFF111827),
                            ),
                          ),
                          Text(
                            '${venue.city} · Venue selected',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFF9DB0CD)
                                  : const Color(0xFF556376),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedVenue = null;
                        _searchCtrl.clear();
                        _step = _Step.search;
                      }),
                      child: const Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Sheet
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0B1322)
                    : const Color(0xFFF8FAFF),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? const Color(0xFF162040)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Full name
                    Text(
                      'FULL NAME',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: isDark
                            ? const Color(0xFF5E708B)
                            : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _ContactField(
                      controller: _nameCtrl,
                      hint: 'Your full name',
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      prefixIcon: Icons.person_outline_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // Phone
                    Text(
                      'PHONE NUMBER',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: isDark
                            ? const Color(0xFF5E708B)
                            : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        // Country selector
                        GestureDetector(
                          onTap: () => _showCountryPicker(colors),
                          child: Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF0F1C35)
                                  : const Color(0xFFF3F6FA),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF1A3060)
                                    : const Color(0xFFD9E1EA),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _selectedCountry.flag,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedCountry.dial,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? const Color(0xFF7A9AC0)
                                        : const Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: isDark
                                      ? const Color(0xFF3A5070)
                                      : Colors.black38,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ContactField(
                            controller: _phoneCtrl,
                            hint: '5XX XXX XX XX',
                            keyboardType: TextInputType.phone,
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    const SizedBox(height: 4),

                    // Error
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Continue button
                    SizedBox(
                      height: 52,
                      child: GestureDetector(
                        onTap: _savingDraft ? null : _onContactContinue,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E4FC7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: _savingDraft
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Continue',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Privacy note
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withValues(alpha: 0.07),
                        border: Border.all(
                          color: AppColors.blue.withValues(alpha: 0.14),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: AppColors.blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? const Color(0xFF9DB0CD)
                                      : const Color(0xFF556376),
                                  height: 1.45,
                                ),
                                children: [
                                  const TextSpan(text: 'Your details are '),
                                  const TextSpan(
                                    text: 'never shared publicly',
                                    style: TextStyle(
                                      color: AppColors.blueDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const TextSpan(
                                    text:
                                        ' and only used for ownership verification.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Belgeler ──────────────────────────────────────────────────────

  Widget _buildDocumentsStep(ColorScheme colors, bool isDark) {
    final uploadedCount =
        (_tradeLicenceUrl != null ? 1 : 0) + (_ownerVideoUrl != null ? 1 : 0);
    const requiredCount = 2;
    final isBusy = _savingDraft || _uploadingLicence || _uploadingVideo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 18,
                    height: 2,
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'STEP 3 OF 4',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                'Upload your',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  height: 1.12,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  colors: isDark
                      ? AppColors.gradientDark
                      : AppColors.gradientLight,
                ).createShader(b),
                blendMode: BlendMode.srcIn,
                child: const Text(
                  'documents.',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                    height: 1.12,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Required to verify your ownership claim.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: isDark ? const Color(0xFFB1B4BB) : Colors.black54,
                ),
              ),
            ],
          ),
        ),

        // Sheet
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0B1322) : const Color(0xFFF8FAFF),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF162040)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Upload progress
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'UPLOAD PROGRESS',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: isDark
                                    ? const Color(0xFF8CA0BE)
                                    : const Color(0xFF54627A),
                              ),
                            ),
                            Text(
                              '$uploadedCount of $requiredCount required',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: uploadedCount / requiredCount,
                            minHeight: 3,
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.06),
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Trade Licence card
                  _UploadCard(
                    label: 'Trade Licence',
                    description: 'Official licence confirming your business.',
                    formats: const ['PDF', 'JPG', 'PNG'],
                    icon: Icons.description_outlined,
                    isRequired: true,
                    uploaded: _tradeLicenceUrl != null,
                    loading: _uploadingLicence,
                    isDark: isDark,
                    onTap: _tradeLicenceUrl != null || _uploadingLicence
                        ? null
                        : _pickTradeLicence,
                    onRemove: _tradeLicenceUrl != null
                        ? () async {
                            setState(() => _tradeLicenceUrl = null);
                            await _saveDraft(stepNumber: 3);
                          }
                        : null,
                  ),
                  const SizedBox(height: 10),

                  // Ownership Video card
                  _UploadCard(
                    label: 'Ownership Video',
                    description:
                        'Short video confirming ownership of the venue.',
                    formats: const ['MP4', 'MOV'],
                    icon: Icons.videocam_outlined,
                    isRequired: true,
                    uploaded: _ownerVideoUrl != null,
                    loading: _uploadingVideo,
                    isDark: isDark,
                    onTap: _ownerVideoUrl != null || _uploadingVideo
                        ? null
                        : _pickOwnerVideo,
                    onRemove: _ownerVideoUrl != null
                        ? () async {
                            setState(() => _ownerVideoUrl = null);
                            await _saveDraft(stepNumber: 3);
                          }
                        : null,
                  ),
                  const SizedBox(height: 14),

                  // Info box
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.07),
                      border: Border.all(
                        color: AppColors.blue.withValues(alpha: 0.14),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          size: 14,
                          color: AppColors.blue,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? const Color(0xFF9DB0CD)
                                    : const Color(0xFF556376),
                                height: 1.5,
                              ),
                              children: [
                                const TextSpan(text: 'Documents are '),
                                const TextSpan(
                                  text: 'encrypted and reviewed privately',
                                  style: TextStyle(
                                    color: AppColors.blueDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(
                                  text: '. They will not be shared publicly.',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (_error != null) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: Color(0xFFFF6B6B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF6B6B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Continue button
                  GestureDetector(
                    onTap: isBusy ? null : _onDocumentsContinue,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: isBusy
                            ? const Color(0xFF1E4FC7).withValues(alpha: 0.5)
                            : const Color(0xFF1E4FC7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: _savingDraft
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Continue',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Skip button
                  GestureDetector(
                    onTap: isBusy ? null : _onDocumentsSkip,
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF162040)
                              : const Color(0xFFD9E1EA),
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          "I don't have them right now",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isBusy
                                ? const Color(0xFF2A3D58)
                                : (isDark
                                      ? const Color(0xFFAFC0DA)
                                      : const Color(0xFF4C5A6E)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 4: Review ────────────────────────────────────────────────────────

  Widget _buildReviewStep(ColorScheme colors, bool isDark) {
    final venue = _selectedVenue!;
    final hasDocuments = _tradeLicenceUrl != null && _ownerVideoUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 18,
                    height: 2,
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'FINAL STEP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                'Review &',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  height: 1.12,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  colors: isDark
                      ? AppColors.gradientDark
                      : AppColors.gradientLight,
                ).createShader(b),
                blendMode: BlendMode.srcIn,
                child: const Text(
                  'confirm.',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                    height: 1.12,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Check your details before submitting your claim.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: isDark ? const Color(0xFFB1B4BB) : Colors.black54,
                ),
              ),
            ],
          ),
        ),

        // Sheet
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0B1322) : const Color(0xFFF8FAFF),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF162040)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Venue card
                  _RevCard(
                    icon: Icons.store_mall_directory_outlined,
                    title: 'VENUE',
                    isDark: isDark,
                    onEdit: () => setState(() {
                      _step = _Step.search;
                      _error = null;
                    }),
                    child: Row(
                      children: [
                        _venueAvatar(venue, colors, size: 44),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                venue.name,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFFC8D8F0)
                                      : const Color(0xFF111827),
                                ),
                              ),
                              if (venue.address.isNotEmpty)
                                Text(
                                  venue.address,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? const Color(0xFF9DB0CD)
                                        : const Color(0xFF556376),
                                    height: 1.4,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Contact card
                  _RevCard(
                    icon: Icons.person_outline_rounded,
                    title: 'CONTACT',
                    isDark: isDark,
                    onEdit: () => setState(() {
                      _step = _Step.contact;
                      _error = null;
                    }),
                    child: Column(
                      children: [
                        _RevContactRow(
                          icon: Icons.person_outline_rounded,
                          label: _nameCtrl.text.trim(),
                          sub: 'Full name',
                          isDark: isDark,
                        ),
                        _RevContactRow(
                          icon: Icons.phone_outlined,
                          label: _fullPhone,
                          sub: 'Phone number',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Documents card
                  _RevCard(
                    icon: Icons.folder_outlined,
                    title: 'DOCUMENTS',
                    isDark: isDark,
                    onEdit: () => setState(() {
                      _step = _Step.documents;
                      _error = null;
                    }),
                    child: Column(
                      children: [
                        _RevDocRow(
                          icon: _tradeLicenceUrl != null
                              ? Icons.check_circle_outline_rounded
                              : Icons.file_copy_outlined,
                          label: _tradeLicenceUrl != null
                              ? 'Trade licence uploaded'
                              : 'Trade licence not uploaded',
                          sub: _tradeLicenceUrl != null
                              ? 'Verified document'
                              : 'Required for faster approval',
                          uploaded: _tradeLicenceUrl != null,
                        ),
                        _RevDocRow(
                          icon: _ownerVideoUrl != null
                              ? Icons.check_circle_outline_rounded
                              : Icons.videocam_outlined,
                          label: _ownerVideoUrl != null
                              ? 'Ownership video uploaded'
                              : 'Ownership video not uploaded',
                          sub: _ownerVideoUrl != null
                              ? 'Video confirmed'
                              : 'Required for approval',
                          uploaded: _ownerVideoUrl != null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Submit button
                  GestureDetector(
                    onTap: _submitting ? null : _submitClaim,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _submitting
                            ? const Color(0xFF1E4FC7).withValues(alpha: 0.5)
                            : const Color(0xFF1E4FC7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.send_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    hasDocuments
                                        ? 'Submit Claim'
                                        : 'Register Without Documents',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (hasDocuments)
                    Text(
                      'Our team will review your claim and notify you once approved.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFF9DB0CD)
                            : const Color(0xFF556376),
                        height: 1.55,
                      ),
                      textAlign: TextAlign.center,
                    )
                  else
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? const Color(0xFF9DB0CD)
                              : const Color(0xFF556376),
                          height: 1.55,
                        ),
                        children: [
                          TextSpan(
                            text: 'You can upload your documents anytime to ',
                          ),
                          TextSpan(
                            text: 'complete your claim',
                            style: TextStyle(
                              color: AppColors.blueDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(text: ' and speed up approval.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _venueAvatar(Venue venue, ColorScheme colors, {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: venue.photoUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.25),
              child: Image.network(
                venue.photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.store_mall_directory_outlined,
                  color: colors.primary,
                  size: size * 0.5,
                ),
              ),
            )
          : Icon(
              Icons.store_mall_directory_outlined,
              color: colors.primary,
              size: size * 0.5,
            ),
    );
  }
}

// ── Widget yardımcıları ───────────────────────────────────────────────────────

class _ContactField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final IconData? prefixIcon;
  final bool isDark;

  const _ContactField({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.prefixIcon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1C35) : const Color(0xFFF3F6FA),
        border: Border.all(
          color: isDark ? const Color(0xFF1A3060) : const Color(0xFFD9E1EA),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (prefixIcon != null)
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Icon(
                prefixIcon,
                size: 17,
                color: isDark ? const Color(0xFF2E4A6A) : Colors.black38,
              ),
            ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFFEEF2FF)
                    : const Color(0xFF111827),
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: isDark ? const Color(0xFF253A58) : Colors.black38,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                isCollapsed: true,
                contentPadding: EdgeInsets.only(
                  left: prefixIcon != null ? 10 : 15,
                  right: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  final String label;
  final String description;
  final List<String> formats;
  final IconData icon;
  final bool isRequired;
  final bool uploaded;
  final bool loading;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _UploadCard({
    required this.label,
    required this.description,
    required this.formats,
    required this.icon,
    required this.isRequired,
    required this.uploaded,
    required this.loading,
    required this.isDark,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final iconBg = isDark
        ? (isRequired ? const Color(0xFF1540A0) : const Color(0xFF1A2A50))
        : (isRequired ? const Color(0xFFDCEAFF) : const Color(0xFFEEF4FF));
    final iconFg = isDark
        ? (isRequired ? const Color(0xFF90B8FF) : const Color(0xFF4A6A9A))
        : (isRequired ? AppColors.blueLight : Colors.black38);
    final borderColor = uploaded
        ? AppColors.teal.withValues(alpha: isDark ? 0.5 : 0.6)
        : isRequired
        ? (isDark ? const Color(0xFF1E3A6A) : const Color(0xFFD9E1EA))
        : (isDark ? const Color(0xFF162040) : const Color(0xFFE8EEF5));
    final cardBg = isDark
        ? (isRequired ? const Color(0xFF0D1A30) : const Color(0xFF0A1428))
        : (isRequired ? const Color(0xFFF0F6FF) : const Color(0xFFF8FAFF));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          border: Border.all(
            color: borderColor,
            width: 1.5,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: uploaded
                    ? const Color(0xFF00D4C8).withValues(alpha: 0.15)
                    : iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.blue,
                        ),
                      ),
                    )
                  : Icon(
                      uploaded ? Icons.check_circle_outline_rounded : icon,
                      size: 21,
                      color: uploaded ? const Color(0xFF00D4C8) : iconFg,
                    ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFC8D8F0)
                              : const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: uploaded
                              ? AppColors.teal.withValues(alpha: 0.15)
                              : isRequired
                              ? const Color(0xFFEA5050).withValues(alpha: 0.15)
                              : (isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.04)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          uploaded
                              ? 'UPLOADED'
                              : (isRequired ? 'REQUIRED' : 'OPTIONAL'),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: uploaded
                                ? const Color(0xFF00D4C8)
                                : isRequired
                                ? const Color(0xFFF08080)
                                : const Color(0xFF3A5070),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? const Color(0xFF9DB0CD)
                          : const Color(0xFF556376),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: formats
                        .map(
                          (f) => Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isRequired
                                  ? AppColors.blue.withValues(alpha: 0.15)
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: isRequired
                                    ? AppColors.blueDark
                                    : (isDark
                                          ? const Color(0xFF9DB0CD)
                                          : const Color(0xFF556376)),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),

            // Upload / remove button
            if (uploaded && onRemove != null)
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Color(0xFFEF4444),
                  ),
                ),
              )
            else
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: uploaded
                      ? const Color(0xFF00D4C8).withValues(alpha: 0.15)
                      : isRequired
                      ? AppColors.blue.withValues(alpha: 0.20)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05)),
                ),
                child: Icon(
                  uploaded ? Icons.check_rounded : Icons.upload_rounded,
                  size: 16,
                  color: uploaded
                      ? const Color(0xFF00D4C8)
                      : isRequired
                      ? AppColors.blueDark
                      : const Color(0xFF2A4060),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RevCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final VoidCallback onEdit;
  final Widget child;

  const _RevCard({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.onEdit,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final kCard = isDark ? const Color(0xFF0D1A30) : Colors.white;
    final kBorder = isDark ? const Color(0xFF1A3060) : const Color(0xFFD9E1EA);
    final kDivider = isDark ? const Color(0x0AFFFFFF) : const Color(0xFFEEF2F8);
    final kLabel = isDark ? const Color(0xFF8CA0BE) : const Color(0xFF54627A);

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: kDivider)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 13, color: AppColors.blue),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: kLabel,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onEdit,
                  child: const Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 11,
                        color: AppColors.blueDark,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.blueDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}

class _RevContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool isDark;

  const _RevContactRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final kLabel = isDark ? const Color(0xFF8AA8CC) : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 14, color: const Color(0xFF4A7ADF)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12.5, color: kLabel)),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark
                      ? const Color(0xFF9DB0CD)
                      : const Color(0xFF556376),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RevDocRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool uploaded;

  const _RevDocRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.uploaded,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: uploaded
                  ? const Color(0xFF00D4C8).withValues(alpha: 0.12)
                  : const Color(0xFFEA5550).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 14,
              color: uploaded
                  ? const Color(0xFF00D4C8)
                  : const Color(0xFFE05050),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: uploaded
                      ? const Color(0xFF00D4C8)
                      : const Color(0xFFE05050),
                ),
              ),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark
                      ? const Color(0xFF9DB0CD)
                      : const Color(0xFF556376),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Ülke seçici bottom sheet ───────────────────────────────────────────────

class _CountryPickerSheet extends StatefulWidget {
  final _CountryCode selected;
  final ColorScheme colors;
  final void Function(_CountryCode) onSelected;

  const _CountryPickerSheet({
    required this.selected,
    required this.colors,
    required this.onSelected,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_CountryCode> _filtered = _countryCodes;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _countryCodes
          : _countryCodes
                .where(
                  (c) =>
                      c.name.toLowerCase().contains(q) ||
                      c.dial.contains(q) ||
                      c.code.toLowerCase().contains(q),
                )
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Select country',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
          // Arama kutusu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Search country or code...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // Liste
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No results',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final c = _filtered[i];
                      final selected = c.code == widget.selected.code;
                      return ListTile(
                        leading: Text(
                          c.flag,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          c.name,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected ? colors.primary : colors.onSurface,
                          ),
                        ),
                        trailing: Text(
                          c.dial,
                          style: TextStyle(
                            color: selected
                                ? colors.primary
                                : colors.onSurface.withValues(alpha: 0.50),
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        onTap: () => widget.onSelected(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Ülke kodu modeli ve listesi ────────────────────────────────────────────

class _CountryCode {
  final String code;
  final String name;
  final String dial;
  final String flag;
  const _CountryCode({
    required this.code,
    required this.name,
    required this.dial,
    required this.flag,
  });
}

const _countryCodes = [
  _CountryCode(code: 'TR', name: 'Turkey', dial: '+90', flag: '🇹🇷'),
  _CountryCode(
    code: 'AE',
    name: 'United Arab Emirates',
    dial: '+971',
    flag: '🇦🇪',
  ),
  _CountryCode(code: 'SA', name: 'Saudi Arabia', dial: '+966', flag: '🇸🇦'),
  _CountryCode(code: 'QA', name: 'Qatar', dial: '+974', flag: '🇶🇦'),
  _CountryCode(code: 'KW', name: 'Kuwait', dial: '+965', flag: '🇰🇼'),
  _CountryCode(code: 'BH', name: 'Bahrain', dial: '+973', flag: '🇧🇭'),
  _CountryCode(code: 'OM', name: 'Oman', dial: '+968', flag: '🇴🇲'),
  _CountryCode(code: 'EG', name: 'Egypt', dial: '+20', flag: '🇪🇬'),
  _CountryCode(code: 'GB', name: 'United Kingdom', dial: '+44', flag: '🇬🇧'),
  _CountryCode(code: 'US', name: 'United States', dial: '+1', flag: '🇺🇸'),
  _CountryCode(code: 'DE', name: 'Germany', dial: '+49', flag: '🇩🇪'),
  _CountryCode(code: 'FR', name: 'France', dial: '+33', flag: '🇫🇷'),
  _CountryCode(code: 'NL', name: 'Netherlands', dial: '+31', flag: '🇳🇱'),
  _CountryCode(code: 'BE', name: 'Belgium', dial: '+32', flag: '🇧🇪'),
  _CountryCode(code: 'CH', name: 'Switzerland', dial: '+41', flag: '🇨🇭'),
  _CountryCode(code: 'AT', name: 'Austria', dial: '+43', flag: '🇦🇹'),
  _CountryCode(code: 'SE', name: 'Sweden', dial: '+46', flag: '🇸🇪'),
  _CountryCode(code: 'NO', name: 'Norway', dial: '+47', flag: '🇳🇴'),
  _CountryCode(code: 'DK', name: 'Denmark', dial: '+45', flag: '🇩🇰'),
  _CountryCode(code: 'RU', name: 'Russia', dial: '+7', flag: '🇷🇺'),
  _CountryCode(code: 'JP', name: 'Japan', dial: '+81', flag: '🇯🇵'),
  _CountryCode(code: 'CN', name: 'China', dial: '+86', flag: '🇨🇳'),
  _CountryCode(code: 'IN', name: 'India', dial: '+91', flag: '🇮🇳'),
  _CountryCode(code: 'AU', name: 'Australia', dial: '+61', flag: '🇦🇺'),
  _CountryCode(code: 'CA', name: 'Canada', dial: '+1', flag: '🇨🇦'),
];
