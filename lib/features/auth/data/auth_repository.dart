import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:flutter/foundation.dart';
import '../../../core/storage/secure_storage.dart';
import 'auth_api.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';

class AuthRepository {
  final AuthApi _api = AuthApi();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '525936528438-c2i235kepeou80utta1rhsgg7jdfhrca.apps.googleusercontent.com',
  );

  static const bool _enableAuthLogs = false;
  void _log(String message) {
    if (kDebugMode && _enableAuthLogs) debugPrint(message);
  }

  Future<void> register(
    String email,
    String password,
    String otpProof, {
    required bool consentGiven,
    required String termsVersionId,
    required String privacyVersionId,
    String consentSource = 'MOBILE',
  }) async {
    final response = await _api.register(
      email: email,
      password: password,
      otpProof: otpProof,
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
    required bool consentGiven,
    required String termsVersionId,
    required String privacyVersionId,
    String consentSource = 'MOBILE',
  }) async {
    final response = await _api.register(
      email: email,
      password: password,
      otpProof: otpProof,
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

  Future<void> requestRegisterOtp(String email) async {
    final response = await _api.requestRegisterOtp(email: email);
    _log('🔥 requestRegisterOtp response = $response');
    if (response['success'] == true) return;
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

  Future<void> forgotPassword(String email) async {
    final response = await _api.forgotPassword(email: email);

    // Backend enumeration yapmıyor → her durumda success sayıyoruz
    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to send reset email');
    }
  }

  Future<bool> login(String email, String password) async {
    _log('🔥 Password login started');

    final response = await _api.login(email: email, password: password);
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

  Future<bool> loginWithGoogle() async {
    _log('🔥 Google login started');

    final googleUser = await _googleSignIn.signIn();
    _log('👤 googleUser = $googleUser');

    if (googleUser == null) return false;

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;

    if (idToken == null) {
      throw Exception('Google idToken is null');
    }

    final response = await _api.loginWithGoogle(idToken: idToken);
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

  Future<void> logout() async {
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken != null) {
      await _api.logout(refreshToken: refreshToken);
    }
    await _googleSignIn.signOut();

    await SecureStorage.clearSession();
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

  Future<Map<String, dynamic>> getMe() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    final me = await _api.me(accessToken: token);
    return _normalizeMeResponse(me);
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

    return me;
  }

  Future<Map<String, dynamic>> switchContext({
    required String lastActiveContext,
    String? activeVenueId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
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
    if (mirror.isNotEmpty) {
      await _api.updateMe(accessToken: token, data: mirror);
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
