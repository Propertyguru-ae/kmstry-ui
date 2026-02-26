import 'package:kmstry_frontend/core/network/api_exception.dart';
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

  Future<void> register(String email, String password, String otpProof) async {
    final response = await _api.register(
      email: email,
      password: password,
      otpProof: otpProof,
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
    String otpProof,
  ) async {
    final response = await _api.register(
      email: email,
      password: password,
      otpProof: otpProof,
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
    if (response['success'] == true) return;
    throw Exception(response['message'] ?? 'Failed to send verification code');
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
    print('🔥 Password login started');

    final response = await _api.login(email: email, password: password);
    print('📡 backend password response = $response');

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
    print('🔥 Google login started');

    final googleUser = await _googleSignIn.signIn();
    print('👤 googleUser = $googleUser');

    if (googleUser == null) return false;

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;

    if (idToken == null) {
      throw Exception('Google idToken is null');
    }

    final response = await _api.loginWithGoogle(idToken: idToken);
    print('📡 backend google response = $response');

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
    final userrr = _api.me(accessToken: token);
    print('👤 googleUser = $userrr');

    return _api.me(accessToken: token);
  }

  Future<void> updateMe(Map<String, dynamic> data) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    await _api.updateMe(accessToken: token, data: data);
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

    print('🟡 updatePermissions called with: $data');

    try {
      await _api.updatePermissions(accessToken: token, data: data);

      print('🟢 updatePermissions success');
    } catch (e) {
      print('🔴 updatePermissions error: $e');
      rethrow;
    }
  }
}
