import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
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
  bool _uploadingPhoto = false;
  bool _saving = false;
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
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        imageQuality: 85,
      );
      if (picked == null) return;
      final file = File(picked.path);
      setState(() {
        _pickedPhoto = file;
        _uploadingPhoto = true;
      });
      await _auth.uploadProfilePhoto(file);
      if (mounted) setState(() => _uploadingPhoto = false);
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
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : Colors.black;
    final canSave = _canSave;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: onSurface),
          onPressed: _saving ? null : () => Navigator.pop(context, false),
        ),
        title: Text(
          'Edit profile',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: canSave ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: canSave
                          ? theme.colorScheme.primary
                          : theme.colorScheme.primary.withValues(alpha: 0.35),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: _buildAvatarImage(isDark),
                      ),
                    ),
                    if (_uploadingPhoto)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: Colors.black.withValues(alpha: 0.4),
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
                  ],
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _uploadingPhoto ? null : _changePhoto,
                  child: Text(
                    'Change photo',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildField(
            label: 'Name',
            controller: _nameController,
            onSurface: onSurface,
            isDark: isDark,
          ),
          _buildUsernameField(onSurface, isDark, theme),
          _buildField(
            label: 'Bio',
            controller: _bioController,
            onSurface: onSurface,
            isDark: isDark,
            maxLines: 3,
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 4),
            Text(
              _saveError!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatarImage(bool isDark) {
    if (_pickedPhoto != null) {
      return Image.file(_pickedPhoto!, fit: BoxFit.cover);
    }
    if (_photoUrl.isNotEmpty) {
      return Image.network(
        _photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _avatarFallback(isDark),
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

  Widget _buildUsernameField(Color onSurface, bool isDark, ThemeData theme) {
    final sub = isDark ? Colors.white54 : Colors.black54;
    Widget? suffix;
    if (_checkingUsername) {
      suffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_usernameAvailable == true) {
      suffix = const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E));
    } else if (_usernameAvailable == false) {
      suffix = Icon(Icons.cancel_rounded, color: theme.colorScheme.error);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Username',
            style: TextStyle(
              color: sub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _usernameController,
            onChanged: _onUsernameChanged,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: onSurface, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              prefixText: '@',
              prefixStyle: TextStyle(color: onSurface, fontSize: 15),
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.grey[300]!,
                ),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.colorScheme.primary),
              ),
            ),
          ),
          if (_usernameError != null) ...[
            const SizedBox(height: 4),
            Text(
              _usernameError!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ] else if (_usernameAvailable == true) ...[
            const SizedBox(height: 4),
            const Text(
              'Username is available.',
              style: TextStyle(color: Color(0xFF22C55E), fontSize: 12),
            ),
          ],
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions.map((s) {
                return ActionChip(
                  label: Text('@$s'),
                  onPressed: () {
                    _usernameController.text = s;
                    _usernameController.selection = TextSelection.fromPosition(
                      TextPosition(offset: s.length),
                    );
                    _onUsernameChanged(s);
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required Color onSurface,
    required bool isDark,
    int maxLines = 1,
  }) {
    final sub = isDark ? Colors.white54 : Colors.black54;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: sub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(color: onSurface, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.grey[300]!,
                ),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
