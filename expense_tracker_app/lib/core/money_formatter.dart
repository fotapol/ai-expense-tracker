import 'money_format_preferences.dart';

String formatMoney(String currency, num amount, {int decimals = 2}) {
  return moneyFormatSettings.format(
    currency,
    amount,
    defaultDecimals: decimals,
  );
}
