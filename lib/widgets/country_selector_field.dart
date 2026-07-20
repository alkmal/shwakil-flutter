import 'package:flutter/material.dart';

import '../services/phone_number_service.dart';

/// A consistent, searchable country-code control for phone number forms.
class CountrySelectorField extends StatelessWidget {
  const CountrySelectorField({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelText = 'الدولة',
    this.compact = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String labelText;
  final bool compact;

  CountryOption get _selected => PhoneNumberService.countries.firstWhere(
    (country) => country.dialCode == value,
    orElse: () => PhoneNumberService.countries.first,
  );

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final country = await showCountrySelectionSheet(context);
        if (country != null) onChanged(country.dialCode);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: const Icon(Icons.public_rounded),
          suffixIcon: const Icon(Icons.search_rounded),
        ),
        child: Text(
          compact ? '+${selected.dialCode}' : selected.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

Future<CountryOption?> showCountrySelectionSheet(BuildContext context) {
  return showModalBottomSheet<CountryOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CountrySelectionSheet(),
  );
}

class _CountrySelectionSheet extends StatefulWidget {
  const _CountrySelectionSheet();

  @override
  State<_CountrySelectionSheet> createState() => _CountrySelectionSheetState();
}

class _CountrySelectionSheetState extends State<_CountrySelectionSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CountryOption> get _countries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return PhoneNumberService.countries;
    final digits = query.replaceAll(RegExp(r'\D'), '');
    return PhoneNumberService.countries.where((country) {
      return country.name.toLowerCase().contains(query) ||
          country.flag.toLowerCase().contains(query) ||
          (digits.isNotEmpty && country.dialCode.contains(digits));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final countries = _countries;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'اختيار الدولة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'ابحث باسم الدولة أو رمز الاتصال',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: countries.isEmpty
                  ? const Center(child: Text('لا توجد دولة مطابقة'))
                  : ListView.separated(
                      itemCount: countries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final country = countries[index];
                        return ListTile(
                          leading: CircleAvatar(child: Text(country.flag)),
                          title: Text(country.name),
                          trailing: Text('+${country.dialCode}'),
                          onTap: () => Navigator.pop(context, country),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
