import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/utils/phone_number_validation.dart';
import 'package:kmstry_frontend/features/venue/data/reservation_phone.dart';
import 'reservation_phone_field.dart';

class VenuePhoneChip extends StatelessWidget {
  final String? phone;
  final VoidCallback? onEdit;
  const VenuePhoneChip({super.key, this.phone, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).brightness == Brightness.dark
        ? AppColors.blue
        : const Color(0xFF086B9C);
    return Material(
      color: AppColors.blue.withValues(alpha: 0.10),
      shape: StadiumBorder(
        side: BorderSide(color: AppColors.blue.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_outlined, size: 15, color: ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  phone ?? 'Reservations phone',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 13, color: ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class VenuePhoneEditor extends StatefulWidget {
  final String? initialPhone;
  final Future<void> Function(String phone) onSave;
  const VenuePhoneEditor({super.key, this.initialPhone, required this.onSave});

  @override
  State<VenuePhoneEditor> createState() => _VenuePhoneEditorState();
}

class _VenuePhoneEditorState extends State<VenuePhoneEditor> {
  late final _controller = ReservationPhoneController(
    initialPhone: widget.initialPhone,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final error = reservationPhoneError(_controller.fullNumber);
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(normalizedValidPhone(_controller.fullNumber)!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not update the phone number. Check your access and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reservations phone',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Customers can call this number from your venue page. Select the country and enter the phone number.',
          ),
          const SizedBox(height: 20),
          ReservationPhoneField(
            inputKey: const ValueKey('edit-reservation-phone'),
            countryKey: const ValueKey('edit-reservation-phone-country'),
            controller: _controller,
            enabled: !_saving,
            errorText: _error,
            onChanged: () {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: _save,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save changes'),
            ),
          ),
        ],
      ),
    ),
  );
}
