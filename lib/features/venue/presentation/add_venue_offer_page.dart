import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_offer_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_offer_repository.dart';

class AddVenueOfferPage extends StatefulWidget {
  final String venueId;

  const AddVenueOfferPage({super.key, required this.venueId});

  @override
  State<AddVenueOfferPage> createState() => _AddVenueOfferPageState();
}

class _AddVenueOfferPageState extends State<AddVenueOfferPage> {
  final _repo = VenueOfferRepository();
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();

  VenueOfferType _type = VenueOfferType.BOGO;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _discountCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  bool get _needsDiscountValue =>
      _type == VenueOfferType.PERCENT_OFF ||
      _type == VenueOfferType.FIXED_DISCOUNT;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'type': _type.name,
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        if (_termsCtrl.text.trim().isNotEmpty) 'terms': _termsCtrl.text.trim(),
        if (_needsDiscountValue && _discountCtrl.text.isNotEmpty)
          'discount_value': double.tryParse(_discountCtrl.text),
      };
      await _repo.create(widget.venueId, data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Offer',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            const Text('Offer type',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _OfferTypeChips(
              selected: _type,
              onSelected: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: 20),
            const Text('Title',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleCtrl,
              decoration: _inputDecoration('e.g. Buy 1 Get 1 Cocktail'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            if (_needsDiscountValue) ...[
              const SizedBox(height: 16),
              Text(
                _type == VenueOfferType.PERCENT_OFF
                    ? 'Discount percentage'
                    : 'Discount amount',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _discountCtrl,
                decoration: _inputDecoration(
                  _type == VenueOfferType.PERCENT_OFF ? '20' : '50',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (_needsDiscountValue &&
                      (v == null ||
                          v.isEmpty ||
                          double.tryParse(v) == null)) {
                    return 'Enter a valid number';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 16),
            const Text('Description (optional)',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descCtrl,
              decoration: _inputDecoration(
                  'e.g. Valid Mon–Thu on all cocktails'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            const Text('Terms & Conditions (optional)',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _termsCtrl,
              decoration: _inputDecoration(
                  'e.g. Cannot be combined with other offers'),
              maxLines: 2,
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
                    : const Text('Create Offer',
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

class _OfferTypeChips extends StatelessWidget {
  final VenueOfferType selected;
  final ValueChanged<VenueOfferType> onSelected;

  const _OfferTypeChips({required this.selected, required this.onSelected});

  static const _options = [
    (VenueOfferType.BOGO, 'BOGO'),
    (VenueOfferType.PERCENT_OFF, '% Off'),
    (VenueOfferType.FIXED_DISCOUNT, 'Fixed Discount'),
    (VenueOfferType.FREE_ITEM, 'Free Item'),
    (VenueOfferType.BUNDLE, 'Bundle'),
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
