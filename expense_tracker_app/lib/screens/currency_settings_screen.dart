import 'package:currency_picker/currency_picker.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/money_format_preferences.dart';
import '../core/redesign_system.dart';
import 'settings_detail_scaffold.dart';
import '../l10n/app_localizations.dart';

class CurrencySettingsScreen extends StatefulWidget {
  const CurrencySettingsScreen({super.key, required this.initialCode});

  final String initialCode;

  @override
  State<CurrencySettingsScreen> createState() => _CurrencySettingsScreenState();
}

class _CurrencySettingsScreenState extends State<CurrencySettingsScreen> {
  static const List<String> _popularCodes = <String>[
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'CNY',
    'CHF',
    'RUB',
  ];

  static const List<String> _allPopularCodes = <String>[
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'CNY',
    'CHF',
    'RUB',
    'AUD',
    'CAD',
    'INR',
    'KRW',
    'BRL',
    'MXN',
    'RSD',
  ];

  late final List<Currency> _allCurrencies;
  late String _selectedCode;
  String _query = '';
  bool _isSaving = false;
  bool _showAll = false;
  late String _symbolPosition;
  late bool _showDecimals;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.initialCode.toUpperCase();
    _allCurrencies = CurrencyService().getAll();
    _symbolPosition = moneyFormatSettings.symbolPosition;
    _showDecimals = moneyFormatSettings.showDecimals;
  }

  List<Currency> _filteredCurrencies() {
    final query = _query.trim().toLowerCase();

    List<Currency> pool;
    if (_showAll || query.isNotEmpty) {
      pool = List<Currency>.of(_allCurrencies);
    } else {
      pool = _allCurrencies
          .where(
            (currency) => _popularCodes.contains(currency.code.toUpperCase()),
          )
          .toList();
    }

    if (query.isNotEmpty) {
      pool = pool.where((currency) {
        final badgeLabel = CurrencyDisplay.labelForCode(
          currency.code,
        ).toLowerCase();
        return currency.code.toLowerCase().contains(query) ||
            currency.name.toLowerCase().contains(query) ||
            currency.symbol.toLowerCase().contains(query) ||
            badgeLabel.contains(query);
      }).toList();
    }

    pool.sort((left, right) {
      final leftIndex = _allPopularCodes.indexOf(left.code.toUpperCase());
      final rightIndex = _allPopularCodes.indexOf(right.code.toUpperCase());
      final leftPinned = leftIndex != -1;
      final rightPinned = rightIndex != -1;
      if (leftPinned && rightPinned) {
        return leftIndex.compareTo(rightIndex);
      }
      if (leftPinned) return -1;
      if (rightPinned) return 1;
      return left.name.compareTo(right.name);
    });
    return pool;
  }

  Future<void> _selectCurrency(Currency currency) async {
    final code = currency.code.toUpperCase();
    if (_isSaving || code == _selectedCode) return;
    setState(() => _isSaving = true);
    try {
      await ApiClient.updateMe(<String, dynamic>{'default_currency': code});
      if (!mounted) return;
      setState(() => _selectedCode = code);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Currency updated to $code.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update currency: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _setSymbolPosition(String value) async {
    await moneyFormatSettings.setSymbolPosition(value);
    if (!mounted) return;
    setState(() => _symbolPosition = moneyFormatSettings.symbolPosition);
  }

  Future<void> _setShowDecimals(bool value) async {
    await moneyFormatSettings.setShowDecimals(value);
    if (!mounted) return;
    setState(() => _showDecimals = moneyFormatSettings.showDecimals);
  }

  Widget _buildCurrencyRow(Currency currency, bool hasDivider) {
    final isSelected = _selectedCode == currency.code.toUpperCase();
    final badgeLabel = CurrencyDisplay.labelForCode(currency.code);
    return InkWell(
      onTap: () => _selectCurrency(currency),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: ShellStyles.iconBadgeDecoration(
                    context,
                    radius: 10,
                  ),
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
                    children: <Widget>[
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
                  Icon(
                    AppIcons.check,
                    color: ShellStyles.textPrimary(context),
                    size: 18,
                  ),
              ],
            ),
          ),
          if (hasDivider)
            Divider(
              height: 1,
              indent: 14,
              endIndent: 14,
              color: ShellStyles.border(context),
            ),
        ],
      ),
    );
  }

  Widget _buildPreferenceChoice({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return SettingsChoiceRow(
      title: title,
      subtitle: subtitle,
      selected: selected,
      selectedBorder: selected,
      onTap: onTap,
    );
  }

  Widget _buildPreviewCard() {
    final currencyName = CurrencyService().findByCode(_selectedCode)?.name;
    final positiveSample = moneyFormatSettings.preview(_selectedCode);
    final negativeSample = moneyFormatSettings.format(_selectedCode, -42.9);
    final subtitle = currencyName == null
        ? _selectedCode
        : '$_selectedCode - $currencyName';

    return SettingsDetailCard(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Preview',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ShellStyles.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  positiveSample,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  negativeSample,
                  style: const TextStyle(
                    color: ShellColors.softRed,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Format options are saved on this device and update supported amount displays, including Home and history.',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencies = _filteredCurrencies();

    return SettingsDetailScaffold(
      title: 'Currency',
      body: SafeArea(
        top: false,
        child: Stack(
          children: <Widget>[
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildPreviewCard(),
                  const SizedBox(height: 16),
                  SettingsSearchField(
                    hintText: 'Search currencies',
                    onChanged: (value) => setState(() {
                      _query = value;
                      if (value.isNotEmpty) {
                        _showAll = true;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: ShellStyles.cardDecoration(context, radius: 18),
                    child: Column(
                      children: <Widget>[
                        for (var index = 0; index < currencies.length; index++)
                          _buildCurrencyRow(
                            currencies[index],
                            index != currencies.length - 1,
                          ),
                        if (_query.isEmpty) ...<Widget>[
                          Divider(
                            height: 1,
                            indent: 14,
                            endIndent: 14,
                            color: ShellStyles.border(context),
                          ),
                          InkWell(
                            onTap: () => setState(() => _showAll = !_showAll),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Text(
                                    _showAll
                                        ? 'Show less'
                                        : 'View all currencies',
                                    style: const TextStyle(
                                      color: ShellColors.softBlue,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _showAll
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
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
                  const SizedBox(height: 24),
                  ShellStyles.sectionLabel(context, 'Symbol position'),
                  const SizedBox(height: 8),
                  _buildPreferenceChoice(
                    title: context.tr('before_the_amount'),
                    subtitle: _previewFor(
                      symbolPosition: 'before',
                      showDecimals: _showDecimals,
                    ),
                    selected: _symbolPosition == 'before',
                    onTap: () => _setSymbolPosition('before'),
                  ),
                  const SizedBox(height: 8),
                  _buildPreferenceChoice(
                    title: context.tr('after_the_amount'),
                    subtitle: _previewFor(
                      symbolPosition: 'after',
                      showDecimals: _showDecimals,
                    ),
                    selected: _symbolPosition == 'after',
                    onTap: () => _setSymbolPosition('after'),
                  ),
                  const SizedBox(height: 24),
                  ShellStyles.sectionLabel(context, 'Decimals'),
                  const SizedBox(height: 8),
                  _buildPreferenceChoice(
                    title: context.tr('show_decimals'),
                    subtitle: _previewFor(
                      symbolPosition: _symbolPosition,
                      showDecimals: true,
                    ),
                    selected: _showDecimals,
                    onTap: () => _setShowDecimals(true),
                  ),
                  const SizedBox(height: 8),
                  _buildPreferenceChoice(
                    title: context.tr('hide_decimals'),
                    subtitle: _previewFor(
                      symbolPosition: _symbolPosition,
                      showDecimals: false,
                    ),
                    selected: !_showDecimals,
                    onTap: () => _setShowDecimals(false),
                  ),
                ],
              ),
            ),
            if (_isSaving)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  String _previewFor({
    required String symbolPosition,
    required bool showDecimals,
  }) {
    return moneyFormatSettings.format(
      _selectedCode,
      1234.56,
      symbolPosition: symbolPosition,
      showDecimals: showDecimals,
    );
  }
}
