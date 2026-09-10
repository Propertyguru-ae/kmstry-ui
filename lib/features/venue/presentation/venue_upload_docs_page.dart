import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';

// Renksiz sabitler — tema bağımsız
const _kBlue = AppColors.blue;
const _kBlueLt = AppColors.blueDark;
const _kPurple = AppColors.magentaDark;
const _kSec = Color(0xFF5B6F8D);
const _kTeal = Color(0xFF00BFB3);

class VenueUploadDocsPage extends StatefulWidget {
  final String venueName;

  const VenueUploadDocsPage({super.key, required this.venueName});

  @override
  State<VenueUploadDocsPage> createState() => _VenueUploadDocsPageState();
}

class _VenueUploadDocsPageState extends State<VenueUploadDocsPage> {
  final _repo = VenueRepository();
  final _picker = ImagePicker();

  String? _licenceUrl;
  String? _videoUrl;
  bool _uploadingLicence = false;
  bool _uploadingVideo = false;
  bool _submitting = false;
  bool _showValidationError = false;

  Future<void> _pickLicence() async {
    if (_uploadingLicence) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() => _uploadingLicence = true);
    try {
      final url = await _uploadFile(File(path), 'licence');
      if (!mounted) return;
      setState(() {
        _licenceUrl = url;
        _showValidationError = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Could not upload trade licence. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingLicence = false);
    }
  }

  Future<void> _pickVideo() async {
    if (_uploadingVideo) return;
    final source = await _showVideoSourceSheet();
    if (source == null) return;
    final xfile = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 2),
    );
    if (xfile == null) return;
    setState(() => _uploadingVideo = true);
    try {
      final url = await _uploadFile(File(xfile.path), 'video');
      if (!mounted) return;
      setState(() {
        _videoUrl = url;
        _showValidationError = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Could not upload video. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<ImageSource?> _showVideoSourceSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kSheet = isDark ? const Color(0xFF0B1322) : Colors.white;
    final kText = isDark ? Colors.white : const Color(0xFF111827);
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: kSheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: _kBlueLt),
              title: Text('Record video', style: TextStyle(color: kText)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.video_library_outlined,
                color: _kBlueLt,
              ),
              title: Text(
                'Choose from gallery',
                style: TextStyle(color: kText),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String> _uploadFile(File file, String type) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/venues/claim-draft/upload?type=$type',
    );
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(await AppRequestHeaders.build(accessToken: token))
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await sendMultipartRequest(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      Map<String, dynamic> data = {};
      try {
        data = Map<String, dynamic>.from(jsonDecode(body) as Map);
      } catch (_) {}
      throw ApiException(statusCode: streamed.statusCode, data: data);
    }
    final decoded = Map<String, dynamic>.from(jsonDecode(body) as Map);
    final url = decoded['url']?.toString();
    if (url == null || url.isEmpty) throw Exception('No URL returned');
    return url;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_licenceUrl == null || _videoUrl == null) {
      setState(() => _showValidationError = true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.submitClaimDocuments(
        tradeLicenceUrl: _licenceUrl!,
        ownerVideoUrl: _videoUrl,
      );
      if (!mounted) return;
      await _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      _showError('Could not submit documents. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showSuccessDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kSheet = isDark ? const Color(0xFF0B1322) : Colors.white;
    final kTitle = isDark ? Colors.white : const Color(0xFF111827);
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: kSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _kTeal.withValues(alpha: 0.12),
                  border: Border.all(color: _kTeal.withValues(alpha: 0.30)),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, size: 34, color: _kTeal),
              ),
              const SizedBox(height: 20),
              Text(
                'Documents Submitted!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kTitle,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Our team will review your ownership claim and get back to you soon.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _kSec, height: 1.55),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _kBlue,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Center(
                    child: Text(
                      'Back to Home',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFBF2020),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? const Color(0xFF06091A) : Colors.white;
    final kSheet = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);
    final kBorder = isDark ? const Color(0xFF1E3060) : const Color(0xFFD9E1EA);
    final kHandle = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
    final kTitle = isDark ? Colors.white : const Color(0xFF111827);
    final kSubtitle = isDark ? const Color(0xFFB1B4BB) : Colors.black54;
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          // ── Hero ─────────────────────────────────────────────────────────
          SizedBox(
            height: top + 200,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Gradient bg
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF0D1F4A),
                              const Color(0xFF1A0D3A),
                              kBg,
                            ]
                          : [
                              const Color(0xFFE8F0FF),
                              const Color(0xFFF0E8FF),
                              kBg,
                            ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: -20,
                        top: 30,
                        child: Transform.rotate(
                          angle: -8 * math.pi / 180,
                          child: Container(
                            width: 120,
                            height: 80,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.white.withValues(alpha: 0.60),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : _kBlue.withValues(alpha: 0.10),
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -10,
                        top: 20,
                        child: Transform.rotate(
                          angle: 6 * math.pi / 180,
                          child: Container(
                            width: 100,
                            height: 70,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.white.withValues(alpha: 0.60),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : _kBlue.withValues(alpha: 0.10),
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Fade overlay to bg
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        kBg.withValues(alpha: 0.20),
                        kBg.withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                ),
                // Lock + venue pill
                Padding(
                  padding: EdgeInsets.only(top: top + 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SpinningLockRing(isDark: isDark),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.fromLTRB(7, 5, 12, 5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : _kBlue.withValues(alpha: 0.06),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : _kBlue.withValues(alpha: 0.15),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1A2A50)
                                    : _kBlue.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.store_outlined,
                                  size: 12,
                                  color: isDark ? _kBlueLt : _kBlue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              widget.venueName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFFBCC5D1)
                                    : const Color(0xFF111827),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Sheet ─────────────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: kSheet,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                border: Border(top: BorderSide(color: kBorder)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: kHandle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Title
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kTitle,
                          letterSpacing: -0.5,
                          height: 1.2,
                        ),
                        children: [
                          const TextSpan(text: 'Almost in.\nUpload to '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: ShaderMask(
                              shaderCallback: (b) => const LinearGradient(
                                colors: [_kBlueLt, _kPurple],
                              ).createShader(b),
                              blendMode: BlendMode.srcIn,
                              child: const Text(
                                'unlock.',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your claim is registered. Upload your documents to complete verification and get full access to your venue account.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: kSubtitle,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'DOCUMENTS NEEDED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: isDark ? _kSec : const Color(0xFF5D6B7B),
                      ),
                    ),
                    const SizedBox(height: 10),

                    _DocCard(
                      icon: Icons.description_outlined,
                      name: 'Trade Licence',
                      required: true,
                      formats: const ['PDF', 'JPG', 'PNG'],
                      uploaded: _licenceUrl != null,
                      loading: _uploadingLicence,
                      isDark: isDark,
                      onTap: _pickLicence,
                    ),
                    const SizedBox(height: 9),

                    _DocCard(
                      icon: Icons.videocam_outlined,
                      name: 'Ownership Video',
                      required: true,
                      formats: const ['MP4', 'MOV'],
                      uploaded: _videoUrl != null,
                      loading: _uploadingVideo,
                      isDark: isDark,
                      onTap: _pickVideo,
                    ),
                    const SizedBox(height: 16),

                    // Teaser
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: _kBlue.withValues(alpha: isDark ? 0.07 : 0.06),
                        border: Border.all(
                          color: _kBlue.withValues(alpha: 0.15),
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                size: 13,
                                color: _kBlueLt,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "After verification you'll unlock",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? _kBlueLt : _kBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _TeaserItem(
                            icon: Icons.bar_chart_outlined,
                            label: 'Venue analytics & guest insights',
                            isDark: isDark,
                          ),
                          const SizedBox(height: 6),
                          _TeaserItem(
                            icon: Icons.campaign_outlined,
                            label: 'Promotions & event management',
                            isDark: isDark,
                          ),
                          const SizedBox(height: 6),
                          _TeaserItem(
                            icon: Icons.star_outline,
                            label: 'Review management & responses',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Validation error
                    if (_showValidationError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 14,
                              color: Color(0xFFFF6B6B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _licenceUrl == null
                                  ? 'Please upload your trade licence first.'
                                  : 'Please upload your ownership video first.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF6B6B),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Submit button
                    GestureDetector(
                      onTap: _submitting ? null : _submit,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: _kBlue,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: _submitting
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.upload_outlined,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Submit Documents',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Later button
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF162040)
                                : const Color(0xFFD9E1EA),
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text(
                            "I'll do this later",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _kSec,
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
      ),
    );
  }
}

// ─── Spinning lock ring ───────────────────────────────────────────────────────

class _SpinningLockRing extends StatefulWidget {
  final bool isDark;
  const _SpinningLockRing({required this.isDark});

  @override
  State<_SpinningLockRing> createState() => _SpinningLockRingState();
}

class _SpinningLockRingState extends State<_SpinningLockRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final kBg = isDark ? const Color(0xFF06091A) : Colors.white;
    final ringBg = isDark
        ? kBg.withValues(alpha: 0.80)
        : Colors.white.withValues(alpha: 0.85);
    final innerGrad = isDark
        ? [const Color(0xFF1A0D3A), const Color(0xFF0D1F4A)]
        : [const Color(0xFFEEF4FF), const Color(0xFFE8F0FF)];
    final innerBorder = isDark
        ? _kPurple.withValues(alpha: 0.30)
        : _kPurple.withValues(alpha: 0.20);
    final ringBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : _kBlue.withValues(alpha: 0.12);

    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => Transform.rotate(
              angle: _ctrl.value * 2 * math.pi,
              child: CustomPaint(
                size: const Size(90, 90),
                painter: _DashedCirclePainter(),
              ),
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: ringBg,
              border: Border.all(color: ringBorder),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: innerGrad,
                  ),
                  border: Border.all(color: innerBorder),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 26,
                  color: _kPurple,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kBlue.withValues(alpha: 0.30)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashCount = 24;
    const dashAngle = 2 * math.pi / dashCount;
    final r = size.width / 2 - 1;
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      final endAngle = startAngle + dashAngle * 0.45;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        startAngle,
        endAngle - startAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Doc card ─────────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final bool required;
  final List<String> formats;
  final bool uploaded;
  final bool loading;
  final bool isDark;
  final VoidCallback onTap;

  const _DocCard({
    required this.icon,
    required this.name,
    required this.required,
    required this.formats,
    required this.uploaded,
    required this.loading,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor = uploaded
        ? (isDark ? const Color(0xFF051E1E) : const Color(0xFFF0FAFA))
        : (required
              ? (isDark ? const Color(0xFF0D1A30) : Colors.white)
              : (isDark ? const Color(0xFF0A1428) : const Color(0xFFF8FAFF)));
    final Color border = uploaded
        ? _kTeal.withValues(alpha: isDark ? 0.35 : 0.45)
        : (required
              ? (isDark ? const Color(0xFF1E3A6A) : const Color(0xFFD9E1EA))
              : (isDark ? const Color(0xFF162040) : const Color(0xFFE8EEF5)));
    final Color iconBg = uploaded
        ? _kTeal.withValues(alpha: 0.15)
        : (required
              ? (isDark ? const Color(0xFF1540A0) : const Color(0xFFDCEAFF))
              : (isDark ? const Color(0xFF162040) : const Color(0xFFF0F4FA)));
    final Color iconColor = uploaded
        ? _kTeal
        : (required
              ? (isDark ? const Color(0xFF90B8FF) : _kBlueLt)
              : (isDark ? const Color(0xFF3A5880) : const Color(0xFF5D6B7B)));
    final Color nameColor = isDark
        ? const Color(0xFFC8D8F0)
        : const Color(0xFF111827);

    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: border,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          borderRadius: BorderRadius.circular(16),
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
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _kBlueLt,
                        ),
                      ),
                    )
                  : Icon(
                      uploaded ? Icons.check_circle_outline : icon,
                      size: 19,
                      color: iconColor,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: nameColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                      if (uploaded)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'UPLOADED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _kTeal,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: required
                                ? const Color(
                                    0xFFEA5050,
                                  ).withValues(alpha: 0.15)
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            required ? 'REQUIRED' : 'OPTIONAL',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: required ? const Color(0xFFF08080) : _kSec,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: formats
                        .map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: uploaded
                                    ? _kTeal.withValues(alpha: 0.10)
                                    : (required
                                          ? _kBlue.withValues(alpha: 0.15)
                                          : (isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.04,
                                                  )
                                                : Colors.black.withValues(
                                                    alpha: 0.05,
                                                  ))),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                f,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: uploaded
                                      ? _kTeal
                                      : (required ? _kBlueLt : _kSec),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            if (!uploaded)
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: required
                      ? _kBlue.withValues(alpha: 0.20)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.upload_outlined,
                  size: 16,
                  color: required ? _kBlueLt : _kSec,
                ),
              )
            else
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _kTeal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, size: 17, color: _kTeal),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Teaser item ──────────────────────────────────────────────────────────────

class _TeaserItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  const _TeaserItem({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final kText = isDark ? const Color(0xFFB1B4BB) : const Color(0xFF5D6B7B);
    return Row(
      children: [
        Icon(icon, size: 13, color: _kBlue),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 11.5, color: kText)),
      ],
    );
  }
}
