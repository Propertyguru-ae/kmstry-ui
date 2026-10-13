import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:flutter/foundation.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/upload_session_identity.dart';
import 'auth_api.dart';
import '../presentation/auth_routes.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:async';
import 'dart:io';
import '../../venue/presentation/profile_preview_page.dart';
import '../../venue_stories/data/venue_story_viewed_cache.dart';
import '../../stories/data/story_viewed_cache.dart';
import '../../../core/push/push_manager.dart';
import '../../chat/data/chat_realtime_service.dart';
import '../../../core/checkin/checkin_ping_manager.dart';
import '../../checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/data/avatar_upload_repository.dart';
import 'apple_sign_in_cancellation.dart';
import '../../../core/user/user_session.dart';
import '../../../core/venue/venue_session.dart';

/// The signed-in account or its local session changed while `/auth/me` was
/// being read, so that response was dropped. An old screen must not retry this
/// read against a different account or Personal/Venue context.
class AccountSessionChangedError extends StateError {
  AccountSessionChangedError() : super('Account session changed during read');
}

/// The owner/session is unchanged, but a mutation superseded this snapshot.
/// Only this case is eligible for a bounded, read-only retry.
class _MeCacheInvalidatedError extends StateError {
  _MeCacheInvalidatedError() : super('Account data changed during read');
}

class _MeReadScope {
  const _MeReadScope(
    this.token,
    this.cacheGeneration,
    this.sessionGeneration,
    this.authRevision,
    this.contextGeneration,
  );
  final String token;
  final int cacheGeneration;
  final int sessionGeneration;
  final int authRevision;
  final int contextGeneration;

  bool matches(_MeReadScope other) =>
      token == other.token &&
      cacheGeneration == other.cacheGeneration &&
      sessionGeneration == other.sessionGeneration &&
      authRevision == other.authRevision &&
      contextGeneration == other.contextGeneration;
}

class _MeReadFlight {
  const _MeReadFlight(this.scope, this.result);
  final _MeReadScope scope;
  final Future<Map<String, dynamic>> result;
}

class AuthRepository {
  AuthRepository({AuthApi? api, Future<void> Function()? signOutProvider})
    : _api = api ?? AuthApi(),
      _signOutProvider = signOutProvider;
  final Future<void> Function()? _signOutProvider;

  // ── One-time app bootstrap ────────────────────────────────────────────────
  /// Call this once from main() after navigatorKey is ready.
  /// Wires up the 401 silent-refresh interceptor in ApiClient.
  static void init({required GlobalKey<NavigatorState> navigatorKey}) {
    PendingPublicMediaService.instance.avatarPublicationChanges
      ..removeListener(_onAvatarPublished)
      ..addListener(_onAvatarPublished);
    ApiClient.onRefreshToken = () async {
      return AuthRepository()._refreshTokenInternal();
    };

    // Several requests can fail together; end the session once.
    ApiClient.onSessionExpired = () => _sessionExpiry ??= _expireSession(
      navigatorKey,
    ).whenComplete(() => _sessionExpiry = null);
  }

  static Future<void>? _sessionExpiry;
  static bool _loggingOut = false;
  static Future<void>? _logoutFlight;

  static Future<void> _expireSession(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    // Requests that finish after logout (or after an earlier expiry) also get
    // 401. That session has already ended and the user is already on the
    // login flow; ending it again would clear state, wake open screens into
    // new requests and reopen the login page in a loop.
    if (_loggingOut) return;
    final hasSession =
        await SecureStorage.getAccessToken() != null ||
        await SecureStorage.getRefreshToken() != null;
    if (!hasSession) return;
    PendingPublicMediaService.instance.clear();
    CheckinPingManager.I.resetSession();
    ActiveCheckinService().clear();
    UserSession.instance.clear();
    VenueSession.instance.clear();
    PushManager.instance.onSessionEnded();
    await SecureStorage.clearSession();
    invalidateMeCache();
    ProfilePreviewPage.clearActionStateCache();
    VenueStoryViewedCache.instance.clear();
    await StoryViewedCache.clearAll();
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AuthRoutes.startupGate,
      (route) => false,
    );
  }

  static void _onAvatarPublished() {
    invalidateMeCache();
    ActiveCheckinService().notifyMediaUpdated();
  }

  Future<String?> _refreshTokenInternal() async {
    return refreshAccessToken();
  }

  // ─────────────────────────────────────────────────────────────────────────

  final AuthApi _api;
  final ApiClient _http = ApiClient();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '525936528438-c2i235kepeou80utta1rhsgg7jdfhrca.apps.googleusercontent.com',
  );
  String? _pendingGoogleIdToken;
  String? _pendingAppleIdentityToken;
  String? _pendingAppleAuthorizationCode;
  String? _pendingAppleFullName;

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
  static int _meCacheGeneration = 0;
  static int _meContextGeneration = 0;
  static _MeReadScope? _getMeCacheScope;
  static _MeReadFlight? _getMeFlight;

  /// Invalidate the cache — call after any operation that changes server-side
  /// user state (switchContext, logout, register, etc.).
  static void invalidateMeCache() {
    _meCacheGeneration++;
    _getMeCache = null;
    _getMeCacheTime = null;
    _getMeCacheScope = null;
    // Do not cancel the HTTP request, but never let a post-mutation/new-session
    // caller join the old read or let its completion replace the new cache.
    _getMeFlight = null;
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

  Future<void> acceptActiveLegalVersions() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated');

    final response = await _api.acceptActiveLegalVersions(accessToken: token);
    if (response['success'] == true) {
      invalidateMeCache();
      return;
    }

    throw Exception(response['message'] ?? 'Failed to accept legal documents');
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
    final revision = SecureStorage.sessionRevision;
    final token = await SecureStorage.getAccessToken();
    final previousRefreshToken = await SecureStorage.getRefreshToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in');
    }
    final response = await _api.changePassword(
      accessToken: token,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to change password');
    }
    await _continueAfterSessionRevocation(
      response,
      revision: revision,
      previousRefreshToken: previousRefreshToken,
    );
  }

  /// Password and email changes end every session on the backend, this one
  /// included, and return a fresh pair for this device. Without storing it
  /// the next request signs out.
  Future<void> _continueAfterSessionRevocation(
    Map<String, dynamic> response, {
    required int revision,
    required String? previousRefreshToken,
  }) async {
    final accessToken = response['accessToken'];
    final refreshToken = response['refreshToken'];
    if (accessToken is! String ||
        refreshToken is! String ||
        previousRefreshToken == null) {
      return;
    }
    final saved = await SecureStorage.saveRefreshedTokens(
      expectedRevision: revision,
      previousRefreshToken: previousRefreshToken,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    if (!saved) return;
    // The server also closed this device's socket and deactivated its push
    // token; reconnect and re-register with the new session.
    PushManager.instance.onSessionEnded();
    unawaited(PushManager.instance.ensureRegisteredIfAllowed());
    unawaited(ChatRealtimeService().connectWithToken(token: accessToken));
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
    final revision = SecureStorage.sessionRevision;
    final token = await SecureStorage.getAccessToken();
    final previousRefreshToken = await SecureStorage.getRefreshToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in');
    }
    final response = await _api.confirmChangeEmail(
      accessToken: token,
      newEmail: newEmail,
      otp: otp,
    );
    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to confirm email change');
    }
    await _continueAfterSessionRevocation(
      response,
      revision: revision,
      previousRefreshToken: previousRefreshToken,
    );
  }

  Future<bool> login(String identifier, String password) async {
    final revision = _beginLogin();
    _log('🔥 Password login started');

    final response = await _api.login(
      identifier: identifier,
      password: password,
    );
    _assertLoginCurrent(revision);

    if (response['success'] == true) {
      await _acceptLogin(response, revision);
      return true;
    }

    throw Exception(response['message'] ?? 'Login failed');
  }

  Future<String?> refreshAccessToken() async {
    if (_loggingOut) return null;
    final revision = SecureStorage.sessionRevision;
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await _api.refresh(refreshToken: refreshToken);

      if (_loggingOut || revision != SecureStorage.sessionRevision) return null;
      if (response['success'] == true) {
        // Backend refresh token'ı her refresh'te ROTATE ediyor (eskisini revoke
        // edip yenisini döndürüyor). Yeni token'ı saklamazsak eski (artık
        // revoke edilmiş) token'la yapılan bir sonraki refresh 401 döner ve
        // kullanıcı beklenmedik şekilde logout olur. Yeni token yoksa (eski
        // backend) eskisine düş.
        final rotatedRefreshToken =
            (response['refreshToken'] as String?) ?? refreshToken;
        final saved = await SecureStorage.saveRefreshedTokens(
          expectedRevision: revision,
          previousRefreshToken: refreshToken,
          accessToken: response['accessToken'],
          refreshToken: rotatedRefreshToken,
        );
        return saved ? response['accessToken'] : null;
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
    bool reusePendingToken = false,
  }) async {
    final revision = _beginLogin();
    _log('🔥 Google login started');

    String? idToken;
    if (reusePendingToken && _pendingGoogleIdToken != null) {
      idToken = _pendingGoogleIdToken;
      _log('♻️ Reusing pending Google idToken after consent');
    } else {
      _pendingGoogleIdToken = null;

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
      _assertLoginCurrent(revision);
      idToken = googleAuth.idToken;
      _pendingGoogleIdToken = idToken;
    }

    if (idToken == null) {
      _pendingGoogleIdToken = null;
      throw Exception('Google idToken is null');
    }

    late final Map<String, dynamic> response;
    try {
      response = await _api.loginWithGoogle(
        idToken: idToken,
        consentGiven: consentGiven,
        termsVersionId: termsVersionId,
        privacyVersionId: privacyVersionId,
        consentSource: consentSource,
      );
    } catch (e) {
      if (!_looksLikeConsentRequired(e)) {
        _pendingGoogleIdToken = null;
      }
      rethrow;
    }
    _assertLoginCurrent(revision);

    if (response['success'] == true) {
      _pendingGoogleIdToken = null;
      await _acceptLogin(response, revision);
      return true;
    }

    _pendingGoogleIdToken = null;
    throw Exception(response['message'] ?? 'Google login failed');
  }

  bool _looksLikeConsentRequired(Object error) {
    if (error is! ApiException) return false;
    final data = error.data;
    final code = data['errorCode'] ?? data['error_code'] ?? data['code'];
    if (code == 'CONSENT_REQUIRED_FOR_SOCIAL_LOGIN' ||
        code == 'LEGAL_CONSENT_REQUIRED') {
      return true;
    }
    final message = data['message']?.toString().toLowerCase() ?? '';
    return message.contains('consent is required for first-time social login');
  }

  Future<bool> loginWithApple({
    bool? consentGiven,
    String? termsVersionId,
    String? privacyVersionId,
    String? consentSource,
    bool reusePendingCredential = false,
  }) async {
    final revision = _beginLogin();
    _log('🍎 Apple login started');

    String? identityToken;
    String? authorizationCode;
    String? fullName;

    if (reusePendingCredential && _pendingAppleIdentityToken != null) {
      identityToken = _pendingAppleIdentityToken;
      authorizationCode = _pendingAppleAuthorizationCode;
      fullName = _pendingAppleFullName;
    } else {
      _pendingAppleIdentityToken = null;
      _pendingAppleAuthorizationCode = null;
      _pendingAppleFullName = null;

      late final AuthorizationCredentialAppleID credential;
      try {
        credential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
      } catch (error) {
        if (isAppleSignInCancellation(error)) return false;
        rethrow;
      }

      _assertLoginCurrent(revision);
      identityToken = credential.identityToken;
      authorizationCode = credential.authorizationCode;

      // Apple only sends the name on the FIRST authorization — forward it so the
      // backend can seed the account. Subsequent logins have null name parts.
      final nameParts = [
        credential.givenName,
        credential.familyName,
      ].where((p) => p != null && p.isNotEmpty).join(' ');
      fullName = nameParts.isEmpty ? null : nameParts;

      _pendingAppleIdentityToken = identityToken;
      _pendingAppleAuthorizationCode = authorizationCode;
      _pendingAppleFullName = fullName;
    }

    if (identityToken == null) {
      _pendingAppleIdentityToken = null;
      _pendingAppleAuthorizationCode = null;
      _pendingAppleFullName = null;
      throw Exception('Apple identityToken is null');
    }

    Map<String, dynamic> response;
    try {
      response = await _api.loginWithApple(
        identityToken: identityToken,
        authorizationCode: authorizationCode,
        fullName: fullName,
        consentGiven: consentGiven,
        termsVersionId: termsVersionId,
        privacyVersionId: privacyVersionId,
        consentSource: consentSource,
      );
    } catch (error) {
      if (!_looksLikeConsentRequired(error)) {
        _pendingAppleIdentityToken = null;
        _pendingAppleAuthorizationCode = null;
        _pendingAppleFullName = null;
      }
      rethrow;
    }
    _assertLoginCurrent(revision);

    if (response['success'] == true) {
      _pendingAppleIdentityToken = null;
      _pendingAppleAuthorizationCode = null;
      _pendingAppleFullName = null;
      await _acceptLogin(response, revision);
      return true;
    }

    _pendingAppleIdentityToken = null;
    _pendingAppleAuthorizationCode = null;
    _pendingAppleFullName = null;
    throw Exception(response['message'] ?? 'Apple login failed');
  }

  int _beginLogin() {
    if (_loggingOut) throw AccountSessionChangedError();
    return SecureStorage.sessionRevision;
  }

  void _assertLoginCurrent(int revision) {
    if (_loggingOut || revision != SecureStorage.sessionRevision) {
      throw AccountSessionChangedError();
    }
  }

  Future<void> _acceptLogin(Map<String, dynamic> response, int revision) async {
    _assertLoginCurrent(revision);
    final saved = await SecureStorage.saveLoginTokens(
      expectedRevision: revision,
      accessToken: response['accessToken'],
      refreshToken: response['refreshToken'],
    );
    if (!saved || _loggingOut) throw AccountSessionChangedError();
    // The server's fresh /auth/me decides Personal vs Venue. Never inherit
    // the previous account's selected venue, check-in or owner-only uploads.
    PendingPublicMediaService.instance.clear();
    CheckinPingManager.I.resetSession();
    ActiveCheckinService().clear();
    UserSession.instance.clear();
    VenueSession.instance.clear();
    invalidateMeCache();
    ProfilePreviewPage.clearActionStateCache();
    VenueStoryViewedCache.instance.clear();
  }

  Future<void> logout() {
    final current = _logoutFlight;
    if (current != null) return current;
    _loggingOut = true;
    return _logoutFlight = _logout().whenComplete(() {
      _loggingOut = false;
      _logoutFlight = null;
    });
  }

  Future<void> _logout() async {
    PendingPublicMediaService.instance.clear();
    CheckinPingManager.I.resetSession();
    invalidateMeCache();
    ActiveCheckinService().clear();
    UserSession.instance.clear();
    VenueSession.instance.clear();
    _pendingGoogleIdToken = null;
    _pendingAppleIdentityToken = null;
    _pendingAppleAuthorizationCode = null;
    _pendingAppleFullName = null;
    final refreshToken = await SecureStorage.getRefreshToken();
    Future<void> revokeRemote() async {
      if (refreshToken == null) return;
      try {
        await _api
            .logout(refreshToken: refreshToken)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Backend logout başarısız olsa da lokal oturumu kapatmaya devam et.
      }
    }

    Future<void> signOutProvider() async {
      try {
        await (_signOutProvider?.call() ?? _googleSignIn.signOut()).timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        // Provider/network failure must never prevent local session cleanup.
      }
    }

    Future<void> clearLocalSession() async {
      PushManager.instance.onSessionEnded();
      // Close sockets and invalidate refresh writes immediately, not after
      // waiting for two independent network/provider operations.
      await SecureStorage.clearSession();
      PendingPublicMediaService.instance.clear();
      invalidateMeCache();
      ProfilePreviewPage.clearActionStateCache();
      VenueStoryViewedCache.instance.clear();
      await StoryViewedCache.clearAll();
    }

    // Keep logout single-flight until all cleanup settles. In particular a
    // late remote revoke must not overlap the next interactive login.
    await Future.wait([revokeRemote(), signOutProvider(), clearLocalSession()]);
  }

  /// Root/global hesap silme: kimlik + bağlı contextler tamamen silinir.
  Future<void> deleteRootAccount() async {
    PendingPublicMediaService.instance.clear();
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _api.deleteAccount(accessToken: token);
    await _googleSignIn.signOut();
    CheckinPingManager.I.stop();
    ActiveCheckinService().clear();
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
    PendingPublicMediaService.instance.clear();
    await _googleSignIn.signOut();
    CheckinPingManager.I.stop();
    ActiveCheckinService().clear();
    PushManager.instance.onSessionEnded();
    await SecureStorage.clearSession();
    ProfilePreviewPage.clearActionStateCache();
  }

  Future<bool> tryGetMe(String accessToken) async {
    for (var attempt = 1; ; attempt++) {
      try {
        if (accessToken != await SecureStorage.getAccessToken()) return false;
        // Session validation must be fresh, but its successful response is
        // also the account data needed by AuthGate/Home. Do not throw that
        // read away.
        await getMe(forceRefresh: true);
        return true;
      } on AccountSessionChangedError {
        // Signing in swaps the previous account's local upload session over
        // to this one during the first read, which drops that read. The
        // session is settled now, so read once more instead of failing login.
        if (attempt == 2) rethrow;
      } catch (e) {
        if (e is ApiException && e.statusCode == 401) {
          return false;
        }
        rethrow; // network vs.
      }
    }
  }

  Future<bool> restoreSession() async {
    final revision = SecureStorage.sessionRevision;
    void requireSameSession() {
      if (_loggingOut || revision != SecureStorage.sessionRevision) {
        throw AccountSessionChangedError();
      }
    }

    requireSameSession();
    final accessToken = await SecureStorage.getAccessToken();
    requireSameSession();
    if (accessToken == null) {
      return false;
    }

    // 1️⃣ Access token ile dene
    final ok = await tryGetMe(accessToken);
    requireSameSession();
    if (ok) return true;

    // 2️⃣ Refresh dene
    final newAccessToken = await refreshAccessToken();
    requireSameSession();
    if (newAccessToken == null) {
      await logout();
      return false;
    }

    // 3️⃣ Yeni token ile tekrar dene
    final okAfterRefresh = await tryGetMe(newAccessToken);
    requireSameSession();
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
    if (_loggingOut) throw AccountSessionChangedError();
    final cacheGeneration = _meCacheGeneration;
    final uploads = PendingPublicMediaService.instance;
    final generation = uploads.sessionGeneration;
    final authRevision = SecureStorage.sessionRevision;
    final contextGeneration = _meContextGeneration;
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    var scope = _MeReadScope(
      token,
      cacheGeneration,
      generation,
      authRevision,
      contextGeneration,
    );
    for (var attempt = 0; ; attempt++) {
      try {
        return await _getMeForScope(
          scope,
          forceRefresh: attempt == 0 && forceRefresh,
        );
      } on _MeCacheInvalidatedError {
        // A check-in/avatar update can invalidate a shared read while Home,
        // notifications and Push are all waiting for it. Join the new read (or
        // its fresh cache) once, never return the superseded response. Do not
        // retry network/authorization errors or cross logout/context changes.
        if (attempt == 1) rethrow;
        final currentToken = await _requireCurrentMeOwner(
          scope,
          requireFreshCache: false,
        );
        scope = _MeReadScope(
          currentToken,
          _meCacheGeneration,
          generation,
          authRevision,
          contextGeneration,
        );
      }
    }
  }

  Future<Map<String, dynamic>> _getMeForScope(
    _MeReadScope scope, {
    required bool forceRefresh,
  }) async {
    _assertCurrentMeScope(scope);

    // Sharing an in-flight fresh read also applies to forceRefresh. Mutations
    // invalidate the generation before asking for a fresh response, so they
    // cannot accidentally join work started before that mutation.
    final flight = _getMeFlight;
    if (flight != null && flight.scope.matches(scope)) {
      final result = await flight.result;
      _assertCurrentMeScope(scope);
      return _copyMeResponse(result);
    }

    if (!forceRefresh &&
        _getMeCacheScope?.matches(scope) == true &&
        _getMeCache != null &&
        _getMeCacheTime != null) {
      final age = DateTime.now().difference(_getMeCacheTime!);
      if (age < _getMeCacheTtl) {
        final cached = _copyMeResponse(_getMeCache!);
        await PendingPublicMediaService.instance.restoreAuthenticatedSession(
          scope.token,
          expectedGeneration: scope.sessionGeneration,
        );
        await _requireCurrentMeOwner(scope);
        _assertCurrentMeScope(scope);
        return cached;
      }
    }

    final next = _MeReadFlight(scope, _readFreshMe(scope));
    _getMeFlight = next;
    try {
      final result = await next.result;
      _assertCurrentMeScope(scope);
      return _copyMeResponse(result);
    } finally {
      if (identical(_getMeFlight, next)) _getMeFlight = null;
    }
  }

  static bool _isCurrentMeSession(_MeReadScope scope) =>
      !_loggingOut &&
      scope.authRevision == SecureStorage.sessionRevision &&
      scope.contextGeneration == _meContextGeneration &&
      PendingPublicMediaService.instance.isCurrentSession(
        scope.sessionGeneration,
      );

  static bool _isCurrentMeScope(_MeReadScope scope) =>
      _isCurrentMeSession(scope) && scope.cacheGeneration == _meCacheGeneration;

  static void _assertCurrentMeScope(_MeReadScope scope) {
    if (!_isCurrentMeSession(scope)) {
      throw AccountSessionChangedError();
    }
    if (scope.cacheGeneration != _meCacheGeneration) {
      throw _MeCacheInvalidatedError();
    }
  }

  static Future<String> _requireCurrentMeOwner(
    _MeReadScope scope, {
    bool requireFreshCache = true,
  }) async {
    final currentToken = await SecureStorage.getAccessToken();
    // A normal silent JWT refresh for the same owner remains valid. The JWT is
    // used only to partition reads; all authorization stays on the server.
    if (!_isCurrentMeSession(scope) ||
        currentToken == null ||
        (scope.token != currentToken &&
            !sameUploadOwner(scope.token, currentToken))) {
      throw AccountSessionChangedError();
    }
    if (requireFreshCache) _assertCurrentMeScope(scope);
    return currentToken;
  }

  Future<Map<String, dynamic>> _readFreshMe(_MeReadScope scope) async {
    final uploads = PendingPublicMediaService.instance;
    final Map<String, dynamic> me;
    try {
      me = await _api.me(accessToken: scope.token);
    } on ApiException catch (error) {
      if ((error.statusCode == 401 || error.statusCode == 403) &&
          _isCurrentMeScope(scope)) {
        // An explicitly denied fresh read must not leave an older successful
        // account response available to the next screen.
        invalidateMeCache();
      }
      rethrow;
    }
    final currentToken = await _requireCurrentMeOwner(scope);
    await uploads.restoreAuthenticatedSession(
      currentToken,
      expectedGeneration: scope.sessionGeneration,
    );
    final readyToken = await _requireCurrentMeOwner(scope);
    _assertCurrentMeScope(scope);
    final normalized = _normalizeMeResponse(me);
    _getMeCache = _copyMeResponse(normalized);
    _getMeCacheTime = DateTime.now();
    _getMeCacheScope = _MeReadScope(
      readyToken,
      scope.cacheGeneration,
      scope.sessionGeneration,
      scope.authRevision,
      scope.contextGeneration,
    );
    return normalized;
  }

  static Map<String, dynamic> _copyMeResponse(Map<String, dynamic> source) {
    dynamic copy(dynamic value) {
      if (value is Map) {
        return value.map((key, item) => MapEntry(key.toString(), copy(item)));
      }
      if (value is List) return value.map(copy).toList();
      return value;
    }

    return source.map((key, value) => MapEntry(key, copy(value)));
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
    final revision = SecureStorage.sessionRevision;
    void requireSameSession() {
      if (_loggingOut || revision != SecureStorage.sessionRevision) {
        throw AccountSessionChangedError();
      }
    }

    requireSameSession();
    final token = await SecureStorage.getAccessToken();
    requireSameSession();
    if (token == null) throw Exception('Not authenticated');
    _meContextGeneration++;
    invalidateMeCache();
    try {
      final response = await _api.switchContext(
        accessToken: token,
        lastActiveContext: lastActiveContext,
        activeVenueId: activeVenueId,
      );
      requireSameSession();
      return response;
    } finally {
      // Reads started while the context mutation was in flight also belong
      // to the previous context, whether that mutation succeeded or failed.
      if (!_loggingOut && revision == SecureStorage.sessionRevision) {
        _meContextGeneration++;
        invalidateMeCache();
      }
    }
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
      _api
          .updateMe(accessToken: token, data: mirror)
          .catchError((_) => <String, dynamic>{});
    }
  }

  Future<void> uploadProfilePhoto1(File file) => uploadProfilePhoto(file);

  Future<void> uploadProfilePhoto(File file) async {
    final session = PendingPublicMediaService.instance.sessionGeneration;
    await AvatarUploadRepository().upload(
      file: file,
      session: session,
      draft: PendingPublicMedia(
        id: PendingPublicMediaService.newUploadId(),
        kind: PendingPublicMediaKind.personalAvatar,
        venueId: null,
        localPath: file.path,
        isVideo: false,
        createdAt: DateTime.now(),
        hasServerReceipt: false,
      ),
    );
    invalidateMeCache();
  }

  Future<void> removeProfilePhoto() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    await _http.delete(
      '/users/me/photo',
      headers: {'Authorization': 'Bearer $token'},
    );
    invalidateMeCache();
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

  /// Account-level optional analytics preference shared by Personal and Venue
  /// contexts. Essential security and crash diagnostics are not controlled by
  /// this preference.
  Future<Map<String, dynamic>> getPrivacyPreferences() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final response = await _http.get(
      '/users/me/privacy-preferences',
      headers: {'Authorization': 'Bearer $token'},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> setOptionalAnalyticsEnabled(bool enabled) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final response = await _http.patch(
      '/users/me/privacy-preferences',
      headers: {'Authorization': 'Bearer $token'},
      body: {'optionalAnalyticsEnabled': enabled},
    );
    invalidateMeCache();
    return Map<String, dynamic>.from(response as Map);
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
