import 'package:flutter/material.dart';
import 'dart:ui'; // Glassmorphism efekti için
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';
import '../../checkin/data/checkin_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  Map<String, dynamic>? _activeCheckin;
  List<String> _moments = [];
  final CheckinRepository _checkinRepo = CheckinRepository();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final me = await AuthRepository().getMe();
          print('ME :  $me');

      List<String> moments = [];

      // 1) Aktif check-in varsa getProfile(checkinId) ile o check-in'in fotoğraflarını al (backend getProfile)
      final activeCheckin = me['active_checkin'];
      final checkinId = activeCheckin is Map ? activeCheckin['id'] as String? : null;
      if (checkinId != null && checkinId.isNotEmpty) {
        try {
          final profile = await _checkinRepo.getCheckinProfile(checkinId);
          if (profile.photos.isNotEmpty) {
            moments = profile.photos.map((p) => p.url).toList();
          }
        } catch (_) {}
      }

      // 2) Yoksa kullanıcının tüm check-in fotoğrafları (GET /users/me/checkin-photos)
      if (moments.isEmpty) {
        try {
          final myPhotos = await _checkinRepo.getMyCheckinPhotos();
          if (myPhotos.isNotEmpty) moments = myPhotos;
        } catch (_) {}
      }

      // 3) Son çare: /auth/me içindeki moments
      if (moments.isEmpty) {
        final fromMe = me['moments'] as List?;
        if (fromMe != null) {
          moments = fromMe.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        }
      }

      if (!mounted) return;
      setState(() {
        _user = me;
        _activeCheckin = me['active_checkin'];
        _moments = moments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final String? backgroundImage = _activeCheckin?['photo_url'] ?? _user?['photo_url'];
    final bool hasImage = backgroundImage != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          /// 1. DİNAMİK ARKA PLAN (Resim yoksa şık bir Gradient)
          Positioned.fill(
            child: hasImage
                ? Image.network(backgroundImage, fit: BoxFit.cover)
                : _buildModernEmptyStateBackground(),
          ),

          /// 2. BLUR & GRADIENT KATMANI (Daha derin bir görünüm için)
          if (!hasImage)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(color: Colors.black.withOpacity(0.2)),
              ),
            ),

          /// 3. STANDART KARARTMA (Yazı okunabilirliği için)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black,
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 0.8],
                ),
              ),
            ),
          ),

          /// 4. İÇERİK
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
             

                const Spacer(),

                /// KULLANICI BİLGİLERİ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_user?['full_name'] ?? 'Guest'} ${_user?['age'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00FF75), // Daha canlı bir yeşil
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Color(0xFF00FF75), blurRadius: 4),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Online',
                            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      /// BIO VEYA NO CHECK-IN UYARISI (Şık bir kutu içinde)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(hasImage ? 0.1 : 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Text(
                          _activeCheckin != null
                              ? (_user?['bio'] ?? 'Hello! This is my bio...')
                              : '✨ You do not have an active check-in.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                /// MOMENTS (Yatay Liste)
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: _moments.isEmpty ? 4 : _moments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return Container(
                        width: 85,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(hasImage ? 0.15 : 0.05),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: _moments.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.network(_moments[index], fit: BoxFit.cover),
                              )
                            : Center(child: Icon(Icons.add_a_photo_outlined, color: Colors.white.withOpacity(0.2))),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 30),

                /// ACTION BUTTON
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasImage ? Colors.transparent : Colors.white,
                        foregroundColor: hasImage ? Colors.white : Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: hasImage ? const BorderSide(color: Colors.white70) : BorderSide.none,
                        ),
                      ),
                      child: const Text(
                        'Edit Profile',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// RESİM OLMADIĞINDA GÖRÜNECEK MODERN GRADIENT
  Widget _buildModernEmptyStateBackground() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
      ),
      child: Stack(
        children: [
          // Sol üst köşe ışığı
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.deepPurple.withOpacity(0.3),
              ),
            ),
          ),
          // Sağ orta ışık
          Positioned(
            top: 200,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withOpacity(0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}