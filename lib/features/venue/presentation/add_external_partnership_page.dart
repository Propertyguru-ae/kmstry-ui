import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';

class AddExternalPartnershipPage extends StatefulWidget {
  final String venueId;

  const AddExternalPartnershipPage({super.key, required this.venueId});

  @override
  State<AddExternalPartnershipPage> createState() =>
      _AddExternalPartnershipPageState();
}

class _AddExternalPartnershipPageState
    extends State<AddExternalPartnershipPage> {
  final _repo = ExternalPartnershipRepository();
  final _formKey = GlobalKey<FormState>();
  final _offerLabelCtrl = TextEditingController();
  final _otherPlatformCtrl = TextEditingController();

  // Yapı aynı kalıyor: tekli seçim (tek platform + tek benefit type).
  ExternalPartnershipPlatform? _platform;
  ExternalPartnershipOfferType _offerType = ExternalPartnershipOfferType.BOGO;
  bool _saving = false;

  static const _platformOptions = [
    (ExternalPartnershipPlatform.THE_ENTERTAINER, 'The Entertainer'),
    (ExternalPartnershipPlatform.COBONE, 'Cobone'),
    (ExternalPartnershipPlatform.GROUPON, 'Groupon'),
    (ExternalPartnershipPlatform.FAZAA, 'Fazaa'),
    (ExternalPartnershipPlatform.ESAAD, 'Esaad'),
    (ExternalPartnershipPlatform.OTHER, 'Other'),
  ];

  static const _offerTypeOptions = [
    (ExternalPartnershipOfferType.BOGO, 'BOGO'),
    (ExternalPartnershipOfferType.PERCENT_OFF, 'Percent Off'),
    (ExternalPartnershipOfferType.VOUCHER, 'Voucher'),
    (ExternalPartnershipOfferType.MEMBERSHIP, 'Membership'),
    (ExternalPartnershipOfferType.OTHER, 'Other'),
  ];

  @override
  void dispose() {
    _offerLabelCtrl.dispose();
    _otherPlatformCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_platform == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a platform')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.create(
        widget.venueId,
        platform: _platform!.name,
        platformLabel: _platform == ExternalPartnershipPlatform.OTHER
            ? _otherPlatformCtrl.text.trim()
            : null,
        offerType: _offerType.name,
        offerLabel: _offerLabelCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showPremiumErrorDialog(
        context,
        message: publicTextErrorMessage(
          e,
          fallback: 'Could not save the partnership. Please try again.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? AppColors.darkBg : Colors.white;
    final kCard = isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FA);
    final kBorder = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kText = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim = isDark ? const Color(0xFF8DA0BD) : const Color(0xFF5D6B7B);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
        title: Text('Add Partnership',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: kText)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kBorder),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
          children: [
            // ── Platform ──────────────────────────────────────────────────
            _SectionTitle(color: AppColors.blue, label: 'Platform', kText: kText),
            const SizedBox(height: 12),
            for (final o in _platformOptions) ...[
              _SelectTile(
                label: o.$2,
                selected: _platform == o.$1,
                isDark: isDark,
                kCard: kCard,
                kBorder: kBorder,
                kText: kText,
                onTap: () => setState(() => _platform = o.$1),
              ),
              const SizedBox(height: 8),
            ],
            if (_platform == ExternalPartnershipPlatform.OTHER) ...[
              const SizedBox(height: 6),
              TextFormField(
                controller: _otherPlatformCtrl,
                style: TextStyle(color: kText, fontSize: 14),
                cursorColor: AppColors.blue,
                decoration: _inputDecoration(
                    'Platform name (e.g. Zomato Pro)', kCard, kBorder, kDim),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
            ],

            const SizedBox(height: 24),

            // ── Benefit type ──────────────────────────────────────────────
            _SectionTitle(
                color: AppColors.teal, label: 'Benefit type', kText: kText),
            const SizedBox(height: 12),
            for (final o in _offerTypeOptions) ...[
              _SelectTile(
                label: o.$2,
                selected: _offerType == o.$1,
                isDark: isDark,
                kCard: kCard,
                kBorder: kBorder,
                kText: kText,
                onTap: () => setState(() => _offerType = o.$1),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 24),

            // ── Benefit description ───────────────────────────────────────
            _SectionTitle(
                color: AppColors.magenta,
                label: 'Benefit description',
                kText: kText),
            const SizedBox(height: 10),
            TextFormField(
              controller: _offerLabelCtrl,
              style: TextStyle(color: kText, fontSize: 14),
              cursorColor: AppColors.blue,
              decoration: _inputDecoration(
                  'e.g. Buy 1 Get 1 on main course, valid Mon–Thu',
                  kCard,
                  kBorder,
                  kDim),
              maxLines: 2,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: PrimaryButton(
            label: 'Add Partnership',
            onPressed: _saving ? null : () => _save(),
            loading: _saving,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
      String hint, Color kCard, Color kBorder, Color kDim) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: kDim.withValues(alpha: 0.75)),
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

// ── Logo renkli nokta + başlık (map filtre başlıklarıyla aynı dil) ──────────────
class _SectionTitle extends StatelessWidget {
  final Color color;
  final String label;
  final Color kText;
  const _SectionTitle(
      {required this.color, required this.label, required this.kText});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: kText,
          ),
        ),
      ],
    );
  }
}

// ── Seçim tile'ı — map'teki partnership sheet tile'ıyla aynı görünüm ────────────
// (Yapı tekli seçim; görünüm sheet stiliyle birebir aynı: mavi→turkuaz onay kutusu.)
class _SelectTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final Color kCard, kBorder, kText;
  final VoidCallback onTap;

  const _SelectTile({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.blue.withValues(alpha: isDark ? 0.16 : 0.10)
                : kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.blue.withValues(alpha: 0.62)
                  : kBorder,
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                      color: AppColors.blue.withValues(alpha: 0.16),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: selected
                      ? const LinearGradient(
                          colors: [AppColors.blue, AppColors.teal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: selected ? null : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : kText.withValues(alpha: isDark ? 0.42 : 0.28),
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 17)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? kText
                        : kText.withValues(alpha: isDark ? 0.78 : 0.72),
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.done_rounded, color: AppColors.teal, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
