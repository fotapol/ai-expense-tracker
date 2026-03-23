import 'redesign_system.dart';

String formatMoney(
  String currency,
  num amount, {
  int decimals = 2,
}) {
  final normalizedCurrency = currency.toUpperCase();
  final symbol = CurrencyDisplay.symbolForCode(normalizedCurrency);
  final absoluteAmount = amount.abs().toStringAsFixed(decimals);
  final sign = amount < 0 ? '-' : '';

  if (symbol != normalizedCurrency) {
    final spacedSymbol = symbol == 'RSD' ? '$symbol ' : symbol;
    return '$sign$spacedSymbol$absoluteAmount';
  }
  return '$sign$normalizedCurrency $absoluteAmount';
}
