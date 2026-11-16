/// Components group matching edges for presentation. Membership alone does not
/// imply every receipt matches every other receipt; decisions still use an edge.
List<List<Map<String, dynamic>>> duplicateGroups(
  List<Map<String, dynamic>> pairs,
) {
  final parents = <String, String>{};
  String root(String id) {
    parents.putIfAbsent(id, () => id);
    var head = id;
    while (parents[head] != head) {
      head = parents[head]!;
    }
    var current = id;
    while (parents[current] != current) {
      final next = parents[current]!;
      parents[current] = head;
      current = next;
    }
    return head;
  }

  for (final pair in pairs) {
    final a = root(pair['first']['id'].toString());
    final b = root(pair['second']['id'].toString());
    if (a != b) parents[b] = a;
  }
  final groups = <String, List<Map<String, dynamic>>>{};
  final seen = <String>{};
  for (final pair in pairs) {
    final ids = [
      pair['first']['id'].toString(),
      pair['second']['id'].toString(),
    ]..sort();
    if (!seen.add(ids.join('/'))) continue;
    groups.putIfAbsent(root(ids.first), () => []).add(pair);
  }
  return groups.values.toList();
}

/// Match the precision shown in the comparison: money has two decimals,
/// quantities three, unit prices four. Ignore JSON formatting and float noise.
bool comparisonNumberSame(Object? a, Object? b, {int decimals = 2}) {
  if (a == null || b == null) return a == b;
  final left = num.tryParse(a.toString()), right = num.tryParse(b.toString());
  if (left == null || right == null || !left.isFinite || !right.isFinite) {
    return a == b;
  }
  return left.toStringAsFixed(decimals) == right.toStringAsFixed(decimals);
}

String comparisonText(Object? value) => (value?.toString() ?? '')
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');

bool samePurchaseMinute(Object? first, Object? second) {
  final a = DateTime.tryParse(first?.toString() ?? '');
  final b = DateTime.tryParse(second?.toString() ?? '');
  if (a == null || b == null) {
    return comparisonText(first) == comparisonText(second);
  }
  return a.millisecondsSinceEpoch ~/ 60000 == b.millisecondsSinceEpoch ~/ 60000;
}

String comparisonUnit(Object? value) => switch (comparisonText(value)) {
  'pcs' || 'piece' || 'pieces' || 'pc' || 'kom' => 'pc',
  'kilogram' || 'kilograms' || 'kg' => 'kg',
  'gram' || 'grams' || 'g' => 'g',
  'liter' || 'litre' || 'liters' || 'litres' || 'l' => 'l',
  'milliliter' || 'millilitre' || 'ml' => 'ml',
  final unit => unit,
};

num? _number(Object? value) {
  final number = num.tryParse(value?.toString() ?? '');
  return number?.isFinite == true ? number : null;
}

num? comparisonUnitPrice(Map<String, dynamic>? item) {
  if (item == null) return null;
  final explicit = _number(item['unit_price']);
  if (explicit != null) return explicit;
  final quantity = _number(item['qty']);
  final amount = _number(item['amount']);
  if (quantity == null || quantity <= 0 || amount == null) return null;
  final beforeDiscount =
      _number(item['amount_before_discount']) ??
      amount + (_number(item['discount_amount']) ?? 0);
  return beforeDiscount / quantity;
}

class ComparedItem {
  const ComparedItem(this.first, this.second);
  final Map<String, dynamic>? first, second;

  bool same(String field) {
    if (first == null || second == null) return false;
    final a = first![field], b = second![field];
    return switch (field) {
      'amount' => comparisonNumberSame(a, b),
      'qty' => comparisonNumberSame(a, b, decimals: 3),
      'unit_price' => comparisonNumberSame(
        comparisonUnitPrice(first),
        comparisonUnitPrice(second),
        decimals: 4,
      ),
      'unit' => comparisonUnit(a) == comparisonUnit(b),
      _ => comparisonText(a) == comparisonText(b),
    };
  }

  bool get identical =>
      first != null &&
      second != null &&
      ['description', 'amount', 'qty', 'unit', 'unit_price'].every(same);
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s.,;:!?()\[\]{}"/\\_\-]+'), ' ')
    .trim();

Set<String> _names(Map<String, dynamic> item) => {
  for (final field in [
    'description',
    'raw_name',
    'normalized_display_name',
    'expanded_name',
    'translatable_name',
  ])
    if (item[field] != null) _normalize(item[field].toString()),
}..remove('');

/// Each occurrence is consumed once. Prefer identical repeated lines, then
/// align equal product names to expose quantity/price differences side by side.
List<ComparedItem> compareItems(List<dynamic> first, List<dynamic> second) {
  final remaining = second
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  final left = first.map((v) => Map<String, dynamic>.from(v as Map)).toList();
  final matches = List<Map<String, dynamic>?>.filled(left.length, null);
  for (final exactPass in [true, false]) {
    for (var i = 0; i < left.length; i++) {
      if (matches[i] != null) continue;
      final names = _names(left[i]);
      final chosen = remaining.indexWhere(
        (b) =>
            names.intersection(_names(b)).isNotEmpty &&
            (!exactPass || ComparedItem(left[i], b).identical),
      );
      if (chosen >= 0) matches[i] = remaining.removeAt(chosen);
    }
  }
  return [
    for (var i = 0; i < left.length; i++) ComparedItem(left[i], matches[i]),
    ...remaining.map((b) => ComparedItem(null, b)),
  ];
}
