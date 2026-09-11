import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';

class EditExternalPartnershipPage extends StatefulWidget {
  final String venueId;
  final ExternalPartnershipModel item;

  const EditExternalPartnershipPage({
    super.key,
    required this.venueId,
    required this.item,
  });

  @override
  State<EditExternalPartnershipPage> createState() =>
      _EditExternalPartnershipPageState();
}

class _EditExternalPartnershipPageState
    extends State<EditExternalPartnershipPage> {
  final _repo = ExternalPartnershipRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _offerLabelCtrl;
  late final TextEditingController _otherPlatformCtrl;

  late ExternalPartnershipPlatform _platform;
  late ExternalPartnershipOfferType _offerType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _platform = widget.item.platform;
    _offerType = widget.item.offerType;
    _offerLabelCtrl = TextEditingController(text: widget.item.offerLabel);
    _otherPlatformCtrl =
        TextEditingController(text: widget.item.platformLabel ?? '');
  }

  @override
  void dispose() {
    _offerLabelCtrl.dispose();
    _otherPlatformCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _repo.update(widget.venueId, widget.item.id, {
        'platform': _platform.name,
        if (_platform == ExternalPartnershipPlatform.OTHER)
          'platform_label': _otherPlatformCtrl.text.trim(),
        'offer_type': _offerType.name,
        'offer_label': _offerLabelCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Partnership',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            const Text('Platform',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _PlatformChips(
              selected: _platform,
              onSelected: (p) => setState(() => _platform = p),
            ),
            if (_platform == ExternalPartnershipPlatform.OTHER) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _otherPlatformCtrl,
                decoration: _inputDecoration('Platform name (e.g. Zomato Pro)'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
            ],
            const SizedBox(height: 20),
            const Text('Benefit type',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _OfferTypeChips(
              selected: _offerType,
              onSelected: (t) => setState(() => _offerType = t),
            ),
            const SizedBox(height: 20),
            const Text('Benefit description',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _offerLabelCtrl,
              decoration: _inputDecoration(
                  'e.g. Buy 1 Get 1 on main course, valid Mon–Thu'),
              maxLines: 2,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          fontSize: 13,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.4)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

class _PlatformChips extends StatelessWidget {
  final ExternalPartnershipPlatform selected;
  final ValueChanged<ExternalPartnershipPlatform> onSelected;

  const _PlatformChips({required this.selected, required this.onSelected});

  static const _options = [
    (ExternalPartnershipPlatform.THE_ENTERTAINER, 'The Entertainer'),
    (ExternalPartnershipPlatform.COBONE, 'Cobone'),
    (ExternalPartnershipPlatform.GROUPON, 'Groupon'),
    (ExternalPartnershipPlatform.FAZAA, 'Fazaa'),
    (ExternalPartnershipPlatform.ESAAD, 'Esaad'),
    (ExternalPartnershipPlatform.OTHER, 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _options
          .map((o) => ChoiceChip(
                label: Text(o.$2),
                selected: selected == o.$1,
                onSelected: (_) => onSelected(o.$1),
              ))
          .toList(),
    );
  }
}

class _OfferTypeChips extends StatelessWidget {
  final ExternalPartnershipOfferType selected;
  final ValueChanged<ExternalPartnershipOfferType> onSelected;

  const _OfferTypeChips({required this.selected, required this.onSelected});

  static const _options = [
    (ExternalPartnershipOfferType.BOGO, 'BOGO'),
    (ExternalPartnershipOfferType.PERCENT_OFF, 'Percent Off'),
    (ExternalPartnershipOfferType.VOUCHER, 'Voucher'),
    (ExternalPartnershipOfferType.MEMBERSHIP, 'Membership'),
    (ExternalPartnershipOfferType.OTHER, 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _options
          .map((o) => ChoiceChip(
                label: Text(o.$2),
                selected: selected == o.$1,
                onSelected: (_) => onSelected(o.$1),
              ))
          .toList(),
    );
  }
}
