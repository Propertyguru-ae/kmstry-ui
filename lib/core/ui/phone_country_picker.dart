import 'package:flutter/material.dart';

// ── Ülke seçici bottom sheet ───────────────────────────────────────────────

class PhoneCountryPickerSheet extends StatefulWidget {
  final PhoneCountry selected;
  final ColorScheme colors;
  final void Function(PhoneCountry) onSelected;

  const PhoneCountryPickerSheet({
    super.key,
    required this.selected,
    required this.colors,
    required this.onSelected,
  });

  @override
  State<PhoneCountryPickerSheet> createState() =>
      _PhoneCountryPickerSheetState();
}

class _PhoneCountryPickerSheetState extends State<PhoneCountryPickerSheet> {
  final _searchCtrl = TextEditingController();
  late final _countries = [
    if (widget.selected.code.isEmpty) internationalPhoneCountry,
    ...phoneCountries,
  ];
  late List<PhoneCountry> _filtered = _countries;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _countries
          : _countries
                .where(
                  (c) =>
                      c.name.toLowerCase().contains(q) ||
                      c.dial.contains(q) ||
                      c.code.toLowerCase().contains(q),
                )
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Select country',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
          // Arama kutusu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Search country or code...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // Liste
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No results',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final c = _filtered[i];
                      final selected = c.code == widget.selected.code;
                      return ListTile(
                        leading: Text(
                          c.flag,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          c.name,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected ? colors.primary : colors.onSurface,
                          ),
                        ),
                        trailing: Text(
                          c.dial,
                          style: TextStyle(
                            color: selected
                                ? colors.primary
                                : colors.onSurface.withValues(alpha: 0.50),
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        onTap: () => widget.onSelected(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Ülke kodu modeli ve listesi ────────────────────────────────────────────

class PhoneCountry {
  final String code;
  final String name;
  final String dial;
  final String flag;
  const PhoneCountry({
    required this.code,
    required this.name,
    required this.dial,
    required this.flag,
  });
}

const internationalPhoneCountry = PhoneCountry(
  code: '',
  name: 'International number',
  dial: '',
  flag: '🌐',
);

const phoneCountries = [
  PhoneCountry(code: 'TR', name: 'Turkey', dial: '+90', flag: '🇹🇷'),
  PhoneCountry(
    code: 'AE',
    name: 'United Arab Emirates',
    dial: '+971',
    flag: '🇦🇪',
  ),
  PhoneCountry(code: 'LB', name: 'Lebanon', dial: '+961', flag: '🇱🇧'),
  PhoneCountry(code: 'SA', name: 'Saudi Arabia', dial: '+966', flag: '🇸🇦'),
  PhoneCountry(code: 'QA', name: 'Qatar', dial: '+974', flag: '🇶🇦'),
  PhoneCountry(code: 'KW', name: 'Kuwait', dial: '+965', flag: '🇰🇼'),
  PhoneCountry(code: 'BH', name: 'Bahrain', dial: '+973', flag: '🇧🇭'),
  PhoneCountry(code: 'OM', name: 'Oman', dial: '+968', flag: '🇴🇲'),
  PhoneCountry(code: 'EG', name: 'Egypt', dial: '+20', flag: '🇪🇬'),
  PhoneCountry(code: 'GB', name: 'United Kingdom', dial: '+44', flag: '🇬🇧'),
  PhoneCountry(code: 'US', name: 'United States', dial: '+1', flag: '🇺🇸'),
  PhoneCountry(code: 'DE', name: 'Germany', dial: '+49', flag: '🇩🇪'),
  PhoneCountry(code: 'FR', name: 'France', dial: '+33', flag: '🇫🇷'),
  PhoneCountry(code: 'NL', name: 'Netherlands', dial: '+31', flag: '🇳🇱'),
  PhoneCountry(code: 'BE', name: 'Belgium', dial: '+32', flag: '🇧🇪'),
  PhoneCountry(code: 'CH', name: 'Switzerland', dial: '+41', flag: '🇨🇭'),
  PhoneCountry(code: 'AT', name: 'Austria', dial: '+43', flag: '🇦🇹'),
  PhoneCountry(code: 'SE', name: 'Sweden', dial: '+46', flag: '🇸🇪'),
  PhoneCountry(code: 'NO', name: 'Norway', dial: '+47', flag: '🇳🇴'),
  PhoneCountry(code: 'DK', name: 'Denmark', dial: '+45', flag: '🇩🇰'),
  PhoneCountry(code: 'RU', name: 'Russia', dial: '+7', flag: '🇷🇺'),
  PhoneCountry(code: 'JP', name: 'Japan', dial: '+81', flag: '🇯🇵'),
  PhoneCountry(code: 'CN', name: 'China', dial: '+86', flag: '🇨🇳'),
  PhoneCountry(code: 'IN', name: 'India', dial: '+91', flag: '🇮🇳'),
  PhoneCountry(code: 'AU', name: 'Australia', dial: '+61', flag: '🇦🇺'),
  PhoneCountry(code: 'CA', name: 'Canada', dial: '+1', flag: '🇨🇦'),
];
