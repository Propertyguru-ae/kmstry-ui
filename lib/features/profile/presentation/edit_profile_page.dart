import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/avatar_crop_helper.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';

/// Instagram tarzı "Edit Profile" ekranı — çalışır.
/// - Foto: image_picker ile seçilip `POST /users/me/photo`'ya yüklenir.
/// - Name / Username / Bio: `PATCH /users/me`.
/// - Username kontrolü iki katman: yazarken debounce'lu ön-kontrol
///   (`GET /users/find-by-username`) + Save'de backend'in kesin 409'u.
class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> user;

  const EditProfilePage({super.key, required this.user});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final AuthRepository _auth = AuthRepository();
  final MatchRepository _matchRepo = MatchRepository();
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;

  String _initialUsername = '';

  File? _pickedPhoto; // yeni seçilen (önizleme için)
  String _photoUrl = '';
  // Aktif check-in'in avatarı (featured foto'dan kırpılmış) — varsa profil
  // fotosunun yerine bu gösterilir ve "Change photo" gizlenir; çünkü aktif
  // check-in boyunca avatar check-in'den yönetilir.
  String _checkinAvatarUrl = '';
  // Aktif check-in'in id'si ve featured (orijinal) foto URL'i — avatar'ı
  // yeniden kırpmak için gerekir.
  String _checkinId = '';
  String _checkinFeaturedUrl = '';
  bool _croppingAvatar = false;
  bool _uploadingPhoto = false;
  bool _removingPhoto = false;
  bool _saving = false;
  bool _photoChanged = false;
  String? _saveError;

  // Username canlı kontrol durumu
  Timer? _usernameDebounce;
  bool _checkingUsername = false;
  bool? _usernameAvailable; // null = bilinmiyor
  String? _usernameError;
  List<String> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: (widget.user['fullName'] ?? widget.user['full_name'] ?? '')
          .toString(),
    );
    _initialUsername =
        (widget.user['username'] ?? widget.user['user_name'] ?? '').toString();
    _usernameController = TextEditingController(text: _initialUsername);
    _bioController = TextEditingController(
      text: (widget.user['bio'] ?? '').toString(),
    );
    _photoUrl = (widget.user['photo'] ?? '').toString();

    final active =
        widget.user['activeCheckin'] ?? widget.user['active_checkin'];
    if (active is Map) {
      _checkinAvatarUrl =
          (active['avatarPhoto'] ?? active['avatar_photo'] ?? '')
              .toString()
              .trim();
      _checkinId = (active['id'] ?? '').toString().trim();
      _checkinFeaturedUrl =
          (active['featuredPhoto'] ?? active['featured_photo'] ?? '')
              .toString()
              .trim();
    }
  }

  bool get _hasCheckinAvatar => _checkinAvatarUrl.isNotEmpty;

  /// Aktif check-in var mı — avatar check-in'den yönetiliyor demektir.
  bool get _hasActiveCheckin => _checkinId.isNotEmpty;

  bool get _hasPersistentProfilePhoto =>
      _photoUrl.isNotEmpty || _pickedPhoto != null;

  bool get _shouldManageCheckinAvatar =>
      _hasActiveCheckin && !_hasPersistentProfilePhoto;

  bool get _hasCheckinAvatarSource =>
      _checkinAvatarUrl.isNotEmpty || _checkinFeaturedUrl.isNotEmpty;

  /// Aktif check-in avatarını yeniden kırpma: orijinal featured foto (yoksa
  /// mevcut avatar) indirilip kare crop ekranı açılır, sonuç yüklenir.
  Future<void> _adjustCheckinAvatar() async {
    if (!_shouldManageCheckinAvatar || _checkinId.isEmpty) return;
    final source = _checkinFeaturedUrl.isNotEmpty
        ? _checkinFeaturedUrl
        : _checkinAvatarUrl;
    if (source.isEmpty) return;

    setState(() => _croppingAvatar = true);
    try {
      final newUrl = await recropCheckinAvatarFromUrl(
        context,
        checkinId: _checkinId,
        featuredUrl: source,
      );
      if (!mounted) return;
      if (newUrl != null && newUrl.isNotEmpty) {
        setState(() {
          _checkinAvatarUrl = newUrl;
          _pickedPhoto = null;
          // Geri dönünce profil sayfası yeniden yüklensin diye değişikliği işaretle;
          // navbar'ın da taze avatarı çekmesi için /auth/me cache'ini geçersiz kıl.
          _photoChanged = true;
        });
        AuthRepository.invalidateMeCache();
        // Check-in id'si değişmedi ama avatarı değişti → navbar'ı koşulsuz uyar,
        // /auth/me'yi taze çekip yeni imzalı avatarı göstersin.
        ActiveCheckinService().notifyMediaUpdated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saveError = 'Avatar could not be updated. Try again.');
      }
    } finally {
      if (mounted) setState(() => _croppingAvatar = false);
    }
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ── Fotoğraf ────────────────────────────────────────────────────────────
  Future<void> _changePhoto() async {
    // Devam eden bir yükleme/silme varken tekrar tetiklenmesini engelle
    // (çift dokunma → çift yükleme / yarış durumu).
    if (_uploadingPhoto || _removingPhoto) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      // Seçilen foto'yu kare avatar olarak kırp; iptal edilirse yükleme yapma.
      final cropped = await cropSquareAvatar(context, File(picked.path));
      if (cropped == null || !mounted) return;
      setState(() {
        _pickedPhoto = cropped;
        _uploadingPhoto = true;
      });
      await _auth.uploadProfilePhoto(cropped);
      if (mounted) {
        setState(() {
          _photoUrl = '';
          _checkinAvatarUrl = '';
          _uploadingPhoto = false;
          _photoChanged = true;
        });
        // Navbar'ı taze avatarla güncelle (/auth/me cache'ini geçersiz kıl + uyar).
        AuthRepository.invalidateMeCache();
        ActiveCheckinService().notifyMediaUpdated();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _pickedPhoto = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload photo. Try again.')),
      );
    }
  }

  Future<void> _removeProfilePhoto() async {
    if (_photoUrl.isEmpty && _pickedPhoto == null) return;
    final confirmed = await showDestructiveConfirmationDialog(
      context,
      title: 'Remove profile photo?',
      message: 'Your active check-in avatar will not be affected.',
      confirmLabel: 'Remove',
      icon: Icons.person_off_rounded,
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _removingPhoto = true;
      _saveError = null;
    });
    try {
      await _auth.removeProfilePhoto();
      if (!mounted) return;
      setState(() {
        _photoUrl = '';
        _pickedPhoto = null;
        _removingPhoto = false;
        _photoChanged = true;
      });
      // Navbar'ı güncelle: foto silindi → kalıcı foto yoksa check-in/placeholder avatarına döner.
      AuthRepository.invalidateMeCache();
      ActiveCheckinService().notifyMediaUpdated();
      showSuccessSnackBar(
        context,
        message: 'Profile photo removed',
        icon: Icons.delete_outline_rounded,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _removingPhoto = false);
      showErrorToast(context, message: 'Could not remove photo. Try again.');
    }
  }

  // ── Username canlı kontrol ──────────────────────────────────────────────
  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    setState(() {
      _usernameAvailable = null;
      _usernameError = null;
      _suggestions = const [];
    });
    final trimmed = value.trim();
    // Değişmediyse kontrol gerekmez.
    if (trimmed.toLowerCase() == _initialUsername.toLowerCase()) {
      setState(() => _checkingUsername = false);
      return;
    }
    if (trimmed.isEmpty) return;
    setState(() => _checkingUsername = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 500), () {
      _checkUsername(trimmed);
    });
  }

  Future<void> _checkUsername(String username) async {
    try {
      final result = await _matchRepo.checkUsernameAvailability(username);
      if (!mounted) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = result.available;
        // Policy hatası (ör. geçersiz karakter) varsa alan altında göster.
        if (!result.available &&
            result.reason != null &&
            !result.reason!.toLowerCase().contains('already')) {
          _usernameError = result.reason;
        }
      });
    } catch (_) {
      // Ön-kontrol başarısızsa engelleme — Save'de backend kesin kontrol yapar.
      if (mounted) setState(() => _checkingUsername = false);
    }
  }

  // ── Kaydet ──────────────────────────────────────────────────────────────
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
      _usernameError = null;
    });

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final bio = _bioController.text.trim();

    final usernameChanged =
        username.isNotEmpty &&
        username.toLowerCase() != _initialUsername.toLowerCase();

    // Canlı kontrol zaten "alınmış" diyorsa backend'e hiç gitme — temiz mesaj.
    if (usernameChanged && _usernameAvailable == false) {
      setState(() {
        _saving = false;
        _usernameError = 'This username is already taken. Try another one.';
      });
      return;
    }

    // Name/username/bio güncellemesi personal-profile endpoint'ine gider —
    // `PATCH /users/me` (updateMe) username'i hiç kabul etmiyor. upsert
    // hem tekilliği doğruluyor (409 + öneriler) hem camelCase alan adları alıyor.
    final data = <String, dynamic>{'bio': bio};
    if (name.isNotEmpty) data['fullName'] = name;
    if (usernameChanged) data['username'] = username;

    try {
      await _auth.upsertPersonalProfile(data);
      AuthRepository.invalidateMeCache();
      // Foto/isim değişikliği sonrası navbar avatarını da tazele (kaydet akışı).
      ActiveCheckinService().notifyMediaUpdated();
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isPublicTextRejection(e)) {
        setState(() {
          _saving = false;
          _saveError = publicTextRejectionMessage;
        });
        return;
      }
      final msg = (e.data['message'] ?? '').toString();
      final lower = msg.toLowerCase();
      final rawSuggestions = e.data['suggestions'];
      final suggestions = rawSuggestions is List
          ? rawSuggestions.map((s) => s.toString()).toList()
          : <String>[];
      // Sadece gerçek çakışma (409 / "in use") = taken. Diğer username
      // mesajları (policy: geçersiz karakter vb.) olduğu gibi gösterilir.
      final isTaken = e.statusCode == 409 || lower.contains('in use');
      final isUsernamePolicy =
          lower.contains('username') || lower.contains('kullanıcı adı');
      setState(() {
        _saving = false;
        if (isTaken) {
          _usernameError = 'This username is already taken. Try another one.';
          _usernameAvailable = false;
          _suggestions = suggestions;
        } else if (isUsernamePolicy) {
          _usernameError = msg;
          _usernameAvailable = false;
          _suggestions = suggestions;
        } else {
          _saveError = 'Could not save. Please try again.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save. Try again.';
      });
    }
  }

  bool get _canSave {
    if (_saving) return false;
    final username = _usernameController.text.trim();
    // Username boş olamaz.
    if (username.isEmpty) return false;
    final usernameChanged =
        username.toLowerCase() != _initialUsername.toLowerCase();
    if (usernameChanged) {
      // Kontrol sürüyorsa veya müsait değilse (X) kaydetme kapalı.
      if (_checkingUsername) return false;
      if (_usernameAvailable == false) return false;
    }
    return true;
  }

  // ── Marka renkleri (logo paleti — her iki temada aynı) ───────────────────
  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _teal = AppColors.teal;

  bool _isDark = true;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFF7FAFF);
  Color get _card => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _cardBorder =>
      _isDark ? const Color(0xFF172445) : const Color(0xFFE1E9F3);
  Color get _fieldFill =>
      _isDark ? const Color(0xFF0F1C35) : const Color(0xFFF2F7FF);
  Color get _fieldBorder =>
      _isDark ? const Color(0xFF1A3060) : const Color(0xFFD9E5F4);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFEEF2FF) : AppColors.lightTextPrimary;
  Color get _hint =>
      _isDark ? const Color(0xFF33486A) : const Color(0xFF95A8C2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _isDark = theme.brightness == Brightness.dark;
    final canSave = _canSave;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(Icons.close_rounded, color: _textPrimary),
            onPressed: _saving
                ? null
                : () => Navigator.pop(context, _photoChanged),
          ),
          title: Text(
            'Edit profile',
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: PrimaryButton(
            label: 'Save changes',
            loading: _saving,
            onPressed: canSave ? _save : null,
          ),
        ),
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cardBorder),
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField(
                      icon: Icons.person_outline_rounded,
                      label: 'NAME',
                      controller: _nameController,
                      hint: 'Your name',
                    ),
                    _buildUsernameField(),
                    _buildField(
                      icon: Icons.notes_rounded,
                      label: 'BIO',
                      controller: _bioController,
                      hint: 'Tell people a little about you',
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _saveError!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Hero: gradient-halkalı avatar + kamera rozeti ─────────────────────────
  Widget _buildHeader() {
    final busy = _uploadingPhoto || _removingPhoto || _croppingAvatar;
    return Column(
      children: [
        const SizedBox(height: 24),
        GestureDetector(
          onTap: busy ? null : _changePhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  gradient: const LinearGradient(
                    colors: [_blueBright, _teal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: SizedBox(
                    width: 132,
                    height: 132,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: _buildAvatarImage(_isDark),
                    ),
                  ),
                ),
              ),
              if (_uploadingPhoto)
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              // Kamera rozeti
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_blueBright, _blue],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: _bg, width: 3),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Foto aksiyonları
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            _photoAction(
              _hasPersistentProfilePhoto ? 'Change photo' : 'Add photo',
              color: _blueBright,
              onTap: busy ? null : _changePhoto,
            ),
            if (_shouldManageCheckinAvatar && _hasCheckinAvatarSource)
              _photoAction(
                'Adjust avatar',
                color: _blueBright,
                loading: _croppingAvatar,
                onTap: busy ? null : _adjustCheckinAvatar,
              ),
            if (_hasPersistentProfilePhoto)
              _photoAction(
                'Remove',
                color: Theme.of(context).colorScheme.error,
                loading: _removingPhoto,
                onTap: busy ? null : _removeProfilePhoto,
              ),
          ],
        ),
      ],
    );
  }

  Widget _photoAction(
    String label, {
    required Color color,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: loading
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
    );
  }

  Widget _buildAvatarImage(bool isDark) {
    if (_pickedPhoto != null) {
      return Image.file(_pickedPhoto!, fit: BoxFit.cover);
    }
    // Profil sayfasıyla aynı öncelik: kalıcı profil fotoğrafı varsa üstün,
    // yoksa check-in avatarı, o da yoksa featured check-in fotoğrafı.
    final displayUrl = _photoUrl.isNotEmpty
        ? _photoUrl
        : (_hasCheckinAvatar ? _checkinAvatarUrl : _checkinFeaturedUrl);
    if (displayUrl.isNotEmpty) {
      return CachedImage(
        displayUrl,
        fit: BoxFit.cover,
        errorWidget: (_) => _avatarFallback(isDark),
      );
    }
    return _avatarFallback(isDark);
  }

  Widget _avatarFallback(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEDEDED),
      child: Icon(
        Icons.person_rounded,
        size: 48,
        color: isDark ? Colors.white38 : Colors.black26,
      ),
    );
  }

  Widget _buildUsernameField() {
    final theme = Theme.of(context);
    Widget? suffix;
    if (_checkingUsername) {
      suffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
        ),
      );
    } else if (_usernameAvailable == true) {
      suffix = const Icon(Icons.check_circle_rounded, color: _teal);
    } else if (_usernameAvailable == false) {
      suffix = Icon(Icons.cancel_rounded, color: theme.colorScheme.error);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(Icons.alternate_email_rounded, 'USERNAME'),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            onChanged: _onUsernameChanged,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: _blue,
            style: TextStyle(color: _textPrimary, fontSize: 15),
            decoration: _fieldDecoration(hint: 'username').copyWith(
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 15, right: 8),
                child: Text(
                  '@',
                  style: TextStyle(
                    color: _blue,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              suffixIcon: suffix,
            ),
          ),
          if (_usernameError != null) ...[
            const SizedBox(height: 6),
            Text(
              _usernameError!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ] else if (_usernameAvailable == true) ...[
            const SizedBox(height: 6),
            const Text(
              'Username is available.',
              style: TextStyle(color: _teal, fontSize: 12),
            ),
          ],
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions.map((s) {
                return GestureDetector(
                  onTap: () {
                    _usernameController.text = s;
                    _usernameController.selection = TextSelection.fromPosition(
                      TextPosition(offset: s.length),
                    );
                    _onUsernameChanged(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _fieldFill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _fieldBorder),
                    ),
                    child: Text(
                      '@$s',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _blueBright,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(icon, label),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: maxLines,
            cursorColor: _blue,
            style: TextStyle(color: _textPrimary, fontSize: 15),
            decoration: _fieldDecoration(hint: hint),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _blueBright),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: _blueBright,
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: _fieldFill,
      hintText: hint,
      hintStyle: TextStyle(color: _hint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _fieldBorder, width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _blue, width: 1.6),
      ),
    );
  }
}
