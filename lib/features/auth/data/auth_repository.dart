import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:flutter/foundation.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/network/api_client.dart';
import 'auth_api.dart';
import '../presentation/auth_routes.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../venue/presentation/profile_preview_page.dart';
import '../../venue_stories/data/venue_story_viewed_cache.dart';
import '../../stories/data/story_viewed_cache.dart';
import '../../../core/push/push_manager.dart';

class AuthRepository {
  // ── One-time app bootstrap ────────────────────────────────────────────────
  /// Call this once from main() after navigatorKey is ready.
  /// Wires up the 401 silent-refresh interceptor in ApiClient.
  static void init({required GlobalKey<NavigatorState> navigatorKey}) {
    ApiClient.onRefreshToken = () async {
      return AuthRepository()._refreshTokenInternal();
    };

    ApiClient.onSessionExpired = () async {
      await SecureStorage.clearSession();
      invalidateMeCache();
      ProfilePreviewPage.clearActionStateCache();
      VenueStoryViewedCache.instance.clear();
      await StoryViewedCache.clearAll();
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AuthRoutes.startupGate,
        (route) => false,
      );
    };
  }

  Future<String?> _refreshTokenInternal() async {
    return refreshAccessToken();
  }

  // ─────────────────────────────────────────────────────────────────────────

  final AuthApi _api = AuthApi();
  final ApiClient _http = ApiClient();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '525936528438-c2i235kepeou80utta1rhsgg7jdfhrca.apps.googleusercontent.com',
  );

  static const bool _enableAuthLogs = false;
  void _log(String message) {
    if (kDebugMode && _enableAuthLogs) debugPrint(message);
  }

  // ── getMe() short-lived cache ─────────────────────────────────────────────
  // Multiple widgets call getMe() simultaneously on startup / account switch.
  // Cache the result for a short window so burst calls hit the API only once.
  static Map<String, dynamic>? _getMeCache;
  static DateTime? _getMeCacheTime;
  static const _getMeCacheTtl = Duration(seconds: 6);

  /// Invalidate the cache — call after any operation that changes server-side
  /// user state (switchContext, logout, register, etc.).
  static void invalidateMeCache() {
    _getMeCache = null;
    _getMeCacheTime = null;
  }

  Future<void> register(
    String email,
    String password,
    String otpProof, {
    bool marketingEmailOptIn = false,
    required bool consentGiven,
    required String termsVersionId,
    required String privacyVersionId,
    String consentSource = 'MOBILE',
  }) async {
    final response = await _api.register(
      email: email,
      password: password,
      otpProof: otpProof,
      marketingEmailOptIn: marketingEmailOptIn,
      consentGiven: consentGiven,
      termsVersionId: termsVersionId,
      privacyVersionId: privacyVersionId,
      consentSource: consentSource,
    );

    if (response['success'] == true) {
      await SecureStorage.saveTokens(
        accessToken: response['accessToken'],
        refreshToken: response['refreshToken'],
      );
    } else {
      throw Exception(response['message'] ?? 'Register failed');
    }
  }

  Future<void> registerAndAutoLogin(
    String email,
    String password,
    String otpProof, {
    bool marketingEmailOptIn = false,
    required bool consentGiven,
    required String termsVersionId,
    required String privacyVersionId,
    String consentSource = 'MOBILE',
  }) async {
    final response = await _api.register(
      email: email,
      password: password,
      otpProof: otpProof,
      marketingEmailOptIn: marketingEmailOptIn,
      consentGiven: consentGiven,
      termsVersionId: termsVersionId,
      privacyVersionId: privacyVersionId,
      consentSource: consentSource,
    );

    if (response['success'] == true) {
      await SecureStorage.saveTokens(
        accessToken: response['accessToken'],
        refreshToken: response['refreshToken'],
      );
      return;
    }

    throw Exception(response['message'] ?? 'Register failed');
  }

  /// On success, returns the server body map (e.g. test `otp`) for the UI layer.
  Future<Map<String, dynamic>> requestRegisterOtp(String email) async {
    final response = await _api.requestRegisterOtp(email: email);
    if (response['success'] == true) return response;
    throw Exception(response['message'] ?? 'Failed to send verification code');
  }

  Future<ActiveLegalVersions> getActiveLegalVersions() async {
    final data = await _api.getActiveLegalVersions();
    final payload = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;

    String? readVersionId(
      Map<String, dynamic> source,
      String camel,
      String snake,
    ) {
      final raw = source[camel] ?? source[snake];
      if (raw is Map) {
        final nested = raw['id'] ?? raw['versionId'] ?? raw['version_id'];
        final value = nested?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      final value = raw?.toString().trim();
      if (value == null || value.isEmpty) return null;
      return value;
    }

    final termsVersionId = readVersionId(
      payload,
      'termsVersionId',
      'terms_version_id',
    );
    final privacyVersionId = readVersionId(
      payload,
      'privacyVersionId',
      'privacy_version_id',
    );

    if (termsVersionId == null ||
        termsVersionId.isEmpty ||
        privacyVersionId == null ||
        privacyVersionId.isEmpty) {
      throw Exception(
        'Active legal policy versions are missing in /legal/active-versions response.',
      );
    }
    return ActiveLegalVersions(
      termsVersionId: termsVersionId,
      privacyVersionId: privacyVersionId,
    );
  }

  Future<List<String>> getUsernameSuggestions(String base) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final response = await _api.getUsernameSuggestions(
      accessToken: token,
      base: base.trim().toLowerCase(),
    );
    final payload = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'] as Map)
        : response;
    final rawSuggestions = payload['suggestions'];
    if (rawSuggestions is! List) return const [];

    final unique = <String>{};
    for (final item in rawSuggestions) {
      final text = item?.toString().trim().toLowerCase() ?? '';
      if (text.isNotEmpty) unique.add(text);
    }
    return unique.toList();
  }

  Future<String> verifyRegisterOtp({
    required String email,
    required String otp,
  }) async {
    final response = await _api.verifyRegisterOtp(email: email, otp: otp);

    if (response['success'] == true) {
      final proof = response['otpProof']?.toString();
      if (proof == null || proof.isEmpty) {
        throw Exception('Missing otpProof from server');
      }
      return proof;
    }

    throw Exception(response['message'] ?? 'Verification code is invalid');
  }

  /// On success returns the server body (e.g. dev-only `resetUrl`) for the UI.
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await _api.forgotPassword(email: email);

    // Backend enumeration yapmıyor → her durumda success sayıyoruz
    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to send reset email');
    }
    return response;
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final response = await _api.resetPassword(
      token: token,
      newPassword: newPassword,
    );
    if (response['success'] == true) return;
    throw Exception(response['message'] ?? 'Failed to reset password');
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in');
    }
    final response = await _api.changePassword(
      accessToken: token,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    if (response['success'] == true) return;
    throw Exception(response['message'] ?? 'Failed to change password');
  }

  Future<Map<String, dynamic>> requestChangeEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in');
    }
    final response = await _api.requestChangeEmail(
      accessToken: token,
      newEmail: newEmail,
      currentPassword: currentPassword,
    );
    if (response['success'] == true) return response;
    throw Exception(response['message'] ?? 'Failed to request email change');
  }

  Future<void> confirmChangeEmail({
    required String newEmail,
    required String otp,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in');
    }
    final response = await _api.confirmChangeEmail(
      accessToken: token,
      newEmail: newEmail,
      otp: otp,
    );
    if (response['success'] == true) return;
    throw Exception(response['message'] ?? 'Failed to confirm email change');
  }

  Future<bool> login(String identifier, String password) async {
    _log('🔥 Password login started');

    final response = await _api.login(identifier: identifier, password: password);
    _log('📡 backend password response = $response');

    if (response['success'] == true) {
      await SecureStorage.saveTokens(
        accessToken: response['accessToken'],
        refreshToken: response['refreshToken'],
      );
      return true;
    }

    throw Exception(response['message'] ?? 'Login failed');
  }

  Future<String?> refreshAccessToken() async {
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await _api.refresh(refreshToken: refreshToken);

      if (response['success'] == true) {
        await SecureStorage.saveTokens(
          accessToken: response['accessToken'],
          refreshToken: refreshToken,
        );
        return response['accessToken'];
      }

      return null;
    } catch (e) {
      // 401 / invalid refresh -> session bitti demek
      if (e is ApiException && e.statusCode == 401) {
        return null;
      }
      rethrow; // network vs gerçek hata
    }
  }

  Future<bool> loginWithGoogle({
    bool? consentGiven,
    String? termsVersionId,
    String? privacyVersionId,
    String? consentSource,
  }) async {
    _log('🔥 Google login started');

    // Önceki (başarısız olabilen) oturumu temizle → her seferinde taze idToken.
    // signOut yoksa plugin cache'lediği hesabı sessizce döndürüp idToken=null
    // verebiliyor ve "bir daha giriş yapılamıyor" durumu oluşuyor.
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    final googleUser = await _googleSignIn.signIn();
    _log('👤 googleUser = $googleUser');

    if (googleUser == null) return false;

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;

    if (idToken == null) {
      throw Exception('Google idToken is null');
    }

    final response = await _api.loginWithGoogle(
      idToken: idToken,
      consentGiven: consentGiven,
      termsVersionId: termsVersionId,
      privacyVersionId: privacyVersionId,
      consentSource: consentSource,
    );
    _log('📡 backend google response = $response');

    if (response['success'] == true) {
      await SecureStorage.saveTokens(
        accessToken: response['accessToken'],
        refreshToken: response['refreshToken'],
      );
      return true;
    }

    throw Exception(response['message'] ?? 'Google login failed');
  }

  Future<bool> loginWithApple({
    bool? consentGiven,
    String? termsVersionId,
    String? privacyVersionId,
    String? consentSource,
  }) async {
    _log('🍎 Apple login started');

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw Exception('Apple identityToken is null');
    }

    // Apple only sends the name on the FIRST authorization — forward it so the
    // backend can seed the account. Subsequent logins have null name parts.
    final nameParts = [credential.givenName, credential.familyName]
        .where((p) => p != null && p.isNotEmpty)
        .join(' ');

    final response = await _api.loginWithApple(
      identityToken: identityToken,
      authorizationCode: credential.authorizationCode,
      fullName: nameParts.isEmpty ? null : nameParts,
      consentGiven: consentGiven,
      termsVersionId: termsVersionId,
      privacyVersionId: privacyVersionId,
      consentSource: consentSource,
    );
    _log('📡 backend apple response = $response');

    if (response['success'] == true) {
      await SecureStorage.saveTokens(
        accessToken: response['accessToken'],
        refreshToken: response['refreshToken'],
      );
      return true;
    }

    throw Exception(response['message'] ?? 'Apple login failed');
  }

  Future<void> logout() async {
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _api.logout(refreshToken: refreshToken);
      } catch (_) {
        // Backend logout başarısız olsa da lokal oturumu kapatmaya devam et.
      }
    }
    await _googleSignIn.signOut();

    // Backend logout tüm device token'ları pasifleştirir; guard'ı sıfırla ki
    // sonraki login aynı cihaz token'ını yeniden aktif kaydetsin.
    PushManager.instance.onSessionEnded();

    await SecureStorage.clearSession();
    invalidateMeCache();
    ProfilePreviewPage.clearActionStateCache();
    VenueStoryViewedCache.instance.clear();
    await StoryViewedCache.clearAll();
  }

  /// Root/global hesap silme: kimlik + bağlı contextler tamamen silinir.
  Future<void> deleteRootAccount() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _api.deleteAccount(accessToken: token);
    await _googleSignIn.signOut();
    PushManager.instance.onSessionEnded();
    await SecureStorage.clearSession();
    ProfilePreviewPage.clearActionStateCache();
    VenueStoryViewedCache.instance.clear();
    await StoryViewedCache.clearAll();
  }

  /// Geriye dönük uyumluluk.
  Future<void> deleteAccount() async => deleteRootAccount();

  /// Aktif kişisel context profilini siler (root kimlik kalır).
  Future<void> deletePersonalContextProfile() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _api.deletePersonalProfile(accessToken: token);
  }

  /// Aktif venue context üyeliğini siler (root kimlik kalır).
  Future<void> deleteVenueContextMembership({required String venueId}) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _api.removeOwnVenueMembership(accessToken: token, venueId: venueId);
  }

  Future<void> deactivateAccount() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _api.deactivateAccount(accessToken: token);
    await _googleSignIn.signOut();
    await SecureStorage.clearSession();
    ProfilePreviewPage.clearActionStateCache();
  }

  Future<bool> tryGetMe(String accessToken) async {
    try {
      await _api.me(accessToken: accessToken);
      return true;
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        return false;
      }
      rethrow; // network vs.
    }
  }

  Future<bool> restoreSession() async {
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) {
      return false;
    }

    // 1️⃣ Access token ile dene
    final ok = await tryGetMe(accessToken);
    if (ok) return true;

    // 2️⃣ Refresh dene
    final newAccessToken = await refreshAccessToken();
    if (newAccessToken == null) {
      await logout();
      return false;
    }

    // 3️⃣ Yeni token ile tekrar dene
    final okAfterRefresh = await tryGetMe(newAccessToken);
    if (!okAfterRefresh) {
      await logout();
      return false;
    }

    return true;
  }

  Future<void> resendVerifyEmail() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    await _api.resendVerifyEmail(accessToken: token);
  }

  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    if (!forceRefresh && _getMeCache != null && _getMeCacheTime != null) {
      final age = DateTime.now().difference(_getMeCacheTime!);
      if (age < _getMeCacheTtl) return Map<String, dynamic>.from(_getMeCache!);
    }

    final me = await _api.me(accessToken: token);
    final normalized = _normalizeMeResponse(me);
    _getMeCache = normalized;
    _getMeCacheTime = DateTime.now();
    return Map<String, dynamic>.from(normalized);
  }

  Map<String, dynamic> _normalizeMeResponse(Map<String, dynamic> source) {
    final me = Map<String, dynamic>.from(source);
    final nestedContext = me['context'];
    if (nestedContext is Map) {
      final context = Map<String, dynamic>.from(nestedContext);
      me['homeRoute'] ??= context['homeRoute'] ?? context['home_route'];
      me['nextAction'] ??= context['nextAction'] ?? context['next_action'];
      me['lastActiveContext'] ??=
          context['lastActiveContext'] ?? context['last_active_context'];
      me['activeVenueId'] ??=
          context['activeVenueId'] ?? context['active_venue_id'];
      me['resolvedActiveVenueId'] ??=
          context['resolvedActiveVenueId'] ??
          context['resolved_active_venue_id'];
      me['hasPersonalProfile'] ??=
          context['hasPersonalProfile'] ?? context['has_personal_profile'];
      me['hasVenueMembership'] ??=
          context['hasVenueMembership'] ?? context['has_venue_membership'];
      me['memberVenues'] ??=
          context['memberVenues'] ?? context['member_venues'];
      me['contextContractValid'] ??=
          context['contextContractValid'] ?? context['context_contract_valid'];
    }

    me['fullName'] ??= me['full_name'];
    me['username'] ??= me['user_name'];
    me['interestedIn'] ??= me['interested_in'];
    me['onboardingStep'] ??= me['onboarding_step'];
    me['activeCheckin'] ??= me['active_checkin'];
    me['hasPersonalProfile'] ??= me['has_personal_profile'];
    me['hasVenueMembership'] ??= me['has_venue_membership'];
    me['memberVenues'] ??= me['member_venues'];
    me['homeRoute'] ??= me['home_route'];
    me['nextAction'] ??= me['next_action'];
    me['lastActiveContext'] ??= me['last_active_context'];
    me['activeVenueId'] ??= me['active_venue_id'];
    me['resolvedActiveVenueId'] ??= me['resolved_active_venue_id'];
    me['bio'] ??= me['bio_text'];
    me['marketingEmailOptIn'] ??= me['marketing_email_opt_in'];
    me['hasPassword'] ??= me['has_password'];
    me['canDeleteCurrentContextProfile'] ??=
        me['can_delete_current_context_profile'];

    return me;
  }

  /// `/auth/me` içinde `authProviders` / `auth_providers` listesinde `password` var mı?
  /// Bilgi yoksa (liste boş veya alan yok) güvenli tarafta kalıp `true` döner (satır gösterilir).
  bool hasLocalPasswordProvider(Map<String, dynamic> me) {
    final hasPassword = me['hasPassword'] ?? me['has_password'];
    if (hasPassword is bool) return hasPassword;

    final list = _authProviderStringsFromMe(me);
    if (list != null) {
      if (list.isEmpty) return true;
      return list.map((e) => e.toLowerCase()).contains('password');
    }
    final flag = me['hasPasswordProvider'] ?? me['has_password_provider'];
    if (flag is bool) return flag;
    return true;
  }

  static List<String>? _authProviderStringsFromMe(Map<String, dynamic> me) {
    final maps = <Map<String, dynamic>>[
      me,
      if (me['data'] is Map) Map<String, dynamic>.from(me['data'] as Map),
      if (me['user'] is Map) Map<String, dynamic>.from(me['user'] as Map),
    ];
    final data = me['data'];
    if (data is Map) {
      final u = data['user'];
      if (u is Map) maps.add(Map<String, dynamic>.from(u));
    }
    for (final m in maps) {
      final raw = m['authProviders'] ?? m['auth_providers'] ?? m['providers'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> switchContext({
    required String lastActiveContext,
    String? activeVenueId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    invalidateMeCache();
    return _api.switchContext(
      accessToken: token,
      lastActiveContext: lastActiveContext,
      activeVenueId: activeVenueId,
    );
  }

  Future<void> updateMe(Map<String, dynamic> data) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    await _api.updateMe(accessToken: token, data: data);
  }

  Future<void> upsertPersonalProfile(Map<String, dynamic> data) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    await _api.upsertPersonalProfile(accessToken: token, data: data);
    invalidateMeCache();

    // Keep legacy /auth/me fields in sync for clients that still read user root fields.
    final mirror = <String, dynamic>{};
    final fullName = (data['fullName'] ?? data['full_name'])?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) {
      mirror['full_name'] = fullName;
    }
    final birthdate = data['birthdate']?.toString().trim();
    if (birthdate != null && birthdate.isNotEmpty) {
      mirror['birthdate'] = birthdate;
    }
    final gender = data['gender']?.toString().trim();
    if (gender != null && gender.isNotEmpty) {
      mirror['gender'] = gender;
    }
    final interestedIn = (data['interestedIn'] ?? data['interested_in'])
        ?.toString()
        .trim();
    if (interestedIn != null && interestedIn.isNotEmpty) {
      mirror['interested_in'] = interestedIn;
    }
    if (data.containsKey('bio')) {
      mirror['bio'] = data['bio'];
    }
    if (data['skipBio'] == true || data['bioOnboardingSkipped'] == true) {
      mirror['skip_bio'] = true;
      mirror['bio_onboarding_skipped'] = true;
    }
    if (mirror.isNotEmpty) {
      // Fire-and-forget: mirror is a legacy sync for old clients.
      // Never block navigation on this call — personal-profile endpoint is the source of truth.
      _api.updateMe(accessToken: token, data: mirror)
          .catchError((_) => <String, dynamic>{});
    }
  }

  Future<void> uploadProfilePhoto1(File file) async {
    final token = await SecureStorage.getAccessToken();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.baseUrl}/users/me/photo'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();

    if (response.statusCode >= 400) {
      throw Exception('Upload failed');
    }
  }

  Future<void> uploadProfilePhoto(File file) async {
    final token = await SecureStorage.getAccessToken();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.baseUrl}/users/me/photo'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: 'profile.jpg', // iOS HEIC olsa bile backend için sorun olmaz
      ),
    );

    final response = await request.send();

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      throw Exception('Upload failed: ${response.statusCode} $body');
    }
  }

  /// Anonymous Mode (KMSTRY+) aç/kapa. Premium değilse backend PREMIUM_REQUIRED döner.
  Future<void> setAnonymous(bool enabled) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _http.patch(
      '/users/me/anonymous',
      headers: {'Authorization': 'Bearer $token'},
      body: {'enabled': enabled},
    );
  }

  /// Read Receipts (KMSTRY+) aç/kapa. Kapatmak premium ister; backend
  /// premium değilse PREMIUM_REQUIRED döner.
  Future<void> setReadReceipts(bool enabled) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _http.patch(
      '/users/me/read-receipts',
      headers: {'Authorization': 'Bearer $token'},
      body: {'enabled': enabled},
    );
  }

  /// Per-category push notification preferences. Partial updates allowed —
  /// only the provided keys change. Mutes push delivery only (in-app kept).
  Future<void> setNotificationPrefs({
    bool? messages,
    bool? invites,
    bool? venueUpdates,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final body = <String, dynamic>{};
    if (messages != null) body['messages'] = messages;
    if (invites != null) body['invites'] = invites;
    if (venueUpdates != null) body['venueUpdates'] = venueUpdates;
    await _http.patch(
      '/users/me/notification-prefs',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
    );
  }

  Future<void> updatePermissions(Map<String, dynamic> data) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    _log('🟡 updatePermissions called with: $data');

    try {
      await _api.updatePermissions(accessToken: token, data: data);

      _log('🟢 updatePermissions success');
    } catch (e) {
      _log('🔴 updatePermissions error: $e');
      rethrow;
    }
  }
}

class ActiveLegalVersions {
  final String termsVersionId;
  final String privacyVersionId;

  const ActiveLegalVersions({
    required this.termsVersionId,
    required this.privacyVersionId,
  });
}
