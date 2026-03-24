import 'package:currency_picker/currency_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class CurrencySettingsScreen extends StatefulWidget {
  const CurrencySettingsScreen({super.key, required this.initialCode});

  final String initialCode;

  @override
  State<CurrencySettingsScreen> createState() => _CurrencySettingsScreenState();
}

class _CurrencySettingsScreenState extends State<CurrencySettingsScreen> {
  // Show just these popular ones by default
  static const List<String> _popularCodes = [
    'USD', 'EUR', 'GBP', 'JPY', 'CNY', 'CHF', 'RUB',
  ];

  // All currencies sorted popular-first
  static const List<String> _allPopularCodes = [
    'USD', 'EUR', 'GBP', 'JPY', 'CNY', 'CHF', 'RUB',
    'AUD', 'CAD', 'INR', 'KRW', 'BRL', 'MXN', 'RSD',
  ];

  static const String _keySymbolPosition = 'currency_symbol_position';
  static const String _keyShowDecimals = 'currency_show_decimals';

  late final List<Currency> _allCurrencies;
  late String _selectedCode;
  String _query = '';
  bool _isSaving = false;
  bool _showAll = false;

  // Format preferences
  String _symbolPosition = 'before';
  bool _showDecimals = true;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.initialCode.toUpperCase();
    _allCurrencies = CurrencyService().getAll();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _symbolPosition = prefs.getString(_keySymbolPosition) ?? 'before';
      _showDecimals = prefs.getBool(_keyShowDecimals) ?? true;
    });
  }

  Future<void> _saveSymbolPosition(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySymbolPosition, value);
    setState(() => _symbolPosition = value);
  }

  Future<void> _saveShowDecimals(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowDecimals, value);
    setState(() => _showDecimals = value);
  }

  List<Currency> _filteredCurrencies() {
    final query = _query.trim().toLowerCase();

    List<Currency> pool;
    if (_showAll || query.isNotEmpty) {
      pool = List.of(_allCurrencies);
    } else {
      // Show only popular currencies
      pool = _allCurrencies.where((c) => _popularCodes.contains(c.code.toUpperCase())).toList();
    }

    if (query.isNotEmpty) {
      pool = pool.where((currency) {
        final badgeLabel = CurrencyDisplay.labelForCode(currency.code).toLowerCase();
        return currency.code.toLowerCase().contains(query) ||
            currency.name.toLowerCase().contains(query) ||
            currency.symbol.toLowerCase().contains(query) ||
            badgeLabel.contains(query);
      }).toList();
    }

    pool.sort((a, b) {
      final aIndex = _allPopularCodes.indexOf(a.code.toUpperCase());
      final bIndex = _allPopularCodes.indexOf(b.code.toUpperCase());
      final aPinned = aIndex != -1;
      final bPinned = bIndex != -1;
      if (aPinned && bPinned) return aIndex.compareTo(bIndex);
      if (aPinned) return -1;
      if (bPinned) return 1;
      return a.name.compareTo(b.name);
    });
    return pool;
  }

  Future<void> _selectCurrency(Currency currency) async {
    final code = currency.code.toUpperCase();
    if (_isSaving || code == _selectedCode) return;
    setState(() => _isSaving = true);
    try {
      await ApiClient.updateMe({'default_currency': code});
      if (!mounted) return;
      setState(() => _selectedCode = code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('settings_currency_updated', params: {'code': code}),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'settings_currency_update_failed',
              params: {'error': error.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildCurrencyRow(Currency currency, bool hasDivider) {
    final isSelected = _selectedCode == currency.code.toUpperCase();
    final badgeLabel = CurrencyDisplay.labelForCode(currency.code);
    return InkWell(
      onTap: () => _selectCurrency(currency),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: ShellStyles.iconBadgeDecoration(context, radius: 10),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: badgeLabel.length > 2 ? 10 : 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currency.name,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currency.code,
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(AppIcons.check, color: ShellStyles.textPrimary(context), size: 18),
              ],
            ),
          ),
          if (hasDivider)
            Divider(height: 1, indent: 14, endIndent: 14, color: ShellStyles.border(context)),
        ],
      ),
    );
  }

  Widget _buildFormatRow({
    required String label,
    required String example,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    example,
                    style: TextStyle(
                      color: ShellColors.softBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(AppIcons.check, color: ShellStyles.textPrimary(context), size: 18),
          ],
        ),
      ),
    );
  }

  String _formatExample(String symbol, double amount, String position) {
    final amountStr = _showDecimals
        ? amount.toStringAsFixed(2)
        : amount.toStringAsFixed(0);
    if (position == 'before') return '$symbol$amountStr';
    return '$amountStr$symbol';
  }

  @override
  Widget build(BuildContext context) {
    final currencies = _filteredCurrencies();
    final exampleSymbol = '\$';

    return SettingsDetailScaffold(
      title: context.tr('settings_currency'),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsSearchField(
                    hintText: context.tr('settings_currency_search'),
                    onChanged: (value) => setState(() {
                      _query = value;
                      if (value.isNotEmpty) _showAll = true;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: ShellStyles.cardDecoration(context, radius: 18),
                    child: Column(
                      children: [
                        for (var index = 0; index < currencies.length; index++)
                          _buildCurrencyRow(
                            currencies[index],
                            index != currencies.length - 1,
                          ),
                        // View All / Show Less toggle
                        if (_query.isEmpty) ...[
                          Divider(height: 1, indent: 14, endIndent: 14, color: ShellStyles.border(context)),
                          InkWell(
                            onTap: () => setState(() => _showAll = !_showAll),
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _showAll ? 'Show less' : 'View all currencies',
                                    style: TextStyle(
                                      color: ShellColors.softBlue,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _showAll ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    color: ShellColors.softBlue,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ShellStyles.sectionLabel(context, 'FORMAT OPTIONS'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: ShellStyles.cardDecoration(context, radius: 18),
                    child: Column(
                      children: [
                        _buildFormatRow(
                          label: 'Before amount',
                          example: _formatExample(exampleSymbol, 100.00, 'before'),
                          isSelected: _symbolPosition == 'before',
                          onTap: () => _saveSymbolPosition('before'),
                        ),
                        Divider(height: 1, indent: 14, endIndent: 14, color: ShellStyles.border(context)),
                        _buildFormatRow(
                          label: 'After amount',
                          example: _formatExample(exampleSymbol, 100.00, 'after'),
                          isSelected: _symbolPosition == 'after',
                          onTap: () => _saveSymbolPosition('after'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ShellStyles.sectionLabel(context, 'DISPLAY OPTIONS'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: ShellStyles.cardDecoration(context, radius: 18),
                    child: SettingsToggleRow(
                      title: 'Show Decimals',
                      subtitle: 'Display cents/minor units',
                      value: _showDecimals,
                      onChanged: _saveShowDecimals,
                    ),
                  ),
                ],
              ),
            ),
            if (_isSaving)
              const Positioned(
                left: 0, right: 0, bottom: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}
