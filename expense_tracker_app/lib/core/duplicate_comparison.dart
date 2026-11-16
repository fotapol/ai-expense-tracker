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

class ComparedItem {
  const ComparedItem(this.first, this.second);
  final Map<String, dynamic>? first, second;

  bool same(String field) {
    if (first == null || second == null) return false;
    final a = first![field], b = second![field];
    final na = num.tryParse(a?.toString() ?? '');
    final nb = num.tryParse(b?.toString() ?? '');
    if (na != null && nb != null) return (na - nb).abs() < 0.000001;
    return a?.toString().trim().toLowerCase() ==
        b?.toString().trim().toLowerCase();
  }

  bool get identical =>
      first != null &&
      second != null &&
      _normalize(first!['description']?.toString() ?? '') ==
          _normalize(second!['description']?.toString() ?? '') &&
      ['amount', 'qty', 'unit', 'unit_price'].every(same);
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
