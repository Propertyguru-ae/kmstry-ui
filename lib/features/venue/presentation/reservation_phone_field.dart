import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/phone_country_picker.dart';
import 'package:kmstry_frontend/core/utils/phone_number_validation.dart';
import 'package:kmstry_frontend/features/venue/data/reservation_phone.dart';

/// Each input owns its selection; no shared/private-contact country state.
class ReservationPhoneController extends ChangeNotifier {
  final number = TextEditingController();
  PhoneCountry _country = phoneCountries.firstWhere((c) => c.code == 'AE');
  bool _updating = false;
  String _lastText = '';

  ReservationPhoneController({String? initialPhone}) {
    setInternationalNumber(initialPhone ?? '');
    number.addListener(_onNumberChanged);
  }

  PhoneCountry get country => _country;

  String get fullNumber {
    final raw = number.text.trim();
    if (raw.isEmpty) return '';
    final parsed = internationalPhoneInput(raw, _country.code);
    if (parsed != null) return parsed;
    if (raw.startsWith('+')) return raw;
    if (raw.startsWith('00')) return '+${raw.substring(2)}';
    final national = raw.replaceAll(RegExp(r'[ ()-]'), '');
    return '${_country.dial}$national';
  }

  void selectCountry(PhoneCountry value) {
    // An unrecognised full number has no safely separable national part. A new
    // explicit country selection must not silently keep its old calling code.
    final replaceInternational = _country.dial.isEmpty && value.dial.isNotEmpty;
    _country = value;
    if (replaceInternational) {
      number.clear();
    }
    notifyListeners();
  }

  void clear() {
    _country = phoneCountries.firstWhere((c) => c.code == 'AE');
    setInternationalNumber('');
  }

  void setInternationalNumber(String value) {
    _updating = true;
    try {
      final raw = value.trim();
      final full = normalizeReservationPhone(
        raw.startsWith('00') ? '+${raw.substring(2)}' : raw,
      );
      if (full != null) {
        final matches =
            phoneCountries.where((c) => full.startsWith(c.dial)).toList()
              ..sort((a, b) => b.dial.length.compareTo(a.dial.length));
        // Shared calling codes (e.g. US/Canada) cannot identify a country on
        // reload. Preserve the current selection when it matches that code.
        final match = matches.isEmpty
            ? internationalPhoneCountry
            : matches.firstWhere(
                (c) =>
                    c.code == _country.code &&
                    c.dial.length == matches.first.dial.length,
                orElse: () => matches.first,
              );
        _country = match;
        _setText(match.dial.isEmpty ? full : full.substring(match.dial.length));
      } else {
        _setText(value);
      }
      _lastText = number.text;
    } finally {
      _updating = false;
    }
    notifyListeners();
  }

  void _setText(String value) {
    number.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _onNumberChanged() {
    if (_updating || number.text == _lastText) return;
    _lastText = number.text;
    final raw = number.text.trim();
    if (raw.startsWith('+') || raw.startsWith('00')) {
      setInternationalNumber(raw);
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    number.removeListener(_onNumberChanged);
    number.dispose();
    super.dispose();
  }
}

class ReservationPhoneField extends StatelessWidget {
  final ReservationPhoneController controller;
  final Key inputKey;
  final Key countryKey;
  final bool enabled;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;
  final String? errorText;
  const ReservationPhoneField({
    super.key,
    required this.controller,
    required this.inputKey,
    required this.countryKey,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
  });

  Future<void> _pickCountry(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<PhoneCountry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PhoneCountryPickerSheet(
        selected: controller.country,
        colors: Theme.of(ctx).colorScheme,
        onSelected: (country) => Navigator.pop(ctx, country),
      ),
    );
    if (!context.mounted || selected == null) return;
    controller.selectCountry(selected);
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final colors = Theme.of(context).colorScheme;
      final fill = dark ? const Color(0xFF0F1C35) : const Color(0xFFF3F6FA);
      final border = dark ? const Color(0xFF1A3060) : const Color(0xFFD9E1EA);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: 'Reservations phone country code',
                button: true,
                child: Material(
                  color: fill,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: border, width: 1.5),
                  ),
                  child: InkWell(
                    key: countryKey,
                    onTap: enabled ? () => _pickCountry(context) : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            controller.country.flag,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            controller.country.dial.isEmpty
                                ? 'Intl.'
                                : controller.country.dial,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: inputKey,
                  controller: controller.number,
                  enabled: enabled,
                  keyboardType: TextInputType.phone,
                  maxLength: 40,
                  autocorrect: false,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: controller.country.dial.isEmpty
                        ? '+ country code and number'
                        : 'Phone number',
                    counterText: '',
                    filled: true,
                    fillColor: fill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: border, width: 1.5),
                    ),
                  ),
                  onChanged: (_) => onChanged?.call(),
                  onFieldSubmitted: (_) => onSubmitted?.call(),
                ),
              ),
            ],
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                errorText!,
                style: TextStyle(fontSize: 12, color: colors.error),
              ),
            ),
        ],
      );
    },
  );
}
