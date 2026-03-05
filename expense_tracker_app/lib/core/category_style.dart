import 'package:flutter/material.dart';

class CategoryStyle {
  CategoryStyle._();

  static const Map<String, Color> _colorByCode = {
    'FOOD': Color(0xFFFF784E),
    'CLOTHING': Color(0xFFC236FF),
    'TRANSPORT': Color(0xFF4FC3F7),
    'UTILITIES': Color(0xFF26D7AE),
    'HEALTH': Color(0xFFFF6E6E),
    'ENTERTAINMENT': Color(0xFFFFD54F),
    'HOME': Color(0xFF00E5FF),
    'ELECTRONICS': Color(0xFF40C4FF),
    'EDUCATION': Color(0xFFD16BFF),
    'PERSONAL_CARE': Color(0xFFFF5CA8),
    'OTHER': Color(0xFFB0BEC5),
    'FLOWERS': Color(0xFF7CFF8A),
    'UNCATEGORIZED': Color(0xFFB0BEC5),
  };

  static const List<Color> _fallbackColors = [
    Color(0xFFFF784E),
    Color(0xFFC236FF),
    Color(0xFF4FC3F7),
    Color(0xFF26D7AE),
    Color(0xFFFF6E6E),
    Color(0xFFFFD54F),
    Color(0xFF40C4FF),
    Color(0xFFD16BFF),
    Color(0xFF7CFF8A),
    Color(0xFF8C9EFF),
    Color(0xFFFFA726),
  ];

  static Color colorForCode(String? code) {
    final normalized = (code ?? '').trim().toUpperCase();
    final direct = _colorByCode[normalized];
    if (direct != null) return direct;
    if (normalized.isEmpty) return _fallbackColors.first;

    var hash = 0;
    for (final unit in normalized.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return _fallbackColors[hash % _fallbackColors.length];
  }

  static IconData iconForCode(String? code) {
    switch ((code ?? '').trim().toUpperCase()) {
      case 'FOOD':
        return Icons.restaurant;
      case 'CLOTHING':
        return Icons.checkroom;
      case 'TRANSPORT':
        return Icons.directions_car;
      case 'UTILITIES':
        return Icons.bolt;
      case 'HEALTH':
        return Icons.favorite;
      case 'ENTERTAINMENT':
        return Icons.movie;
      case 'HOME':
        return Icons.home;
      case 'ELECTRONICS':
        return Icons.devices;
      case 'EDUCATION':
        return Icons.school;
      case 'PERSONAL_CARE':
        return Icons.spa;
      case 'FLOWERS':
        return Icons.local_florist;
      case 'OTHER':
      case 'UNCATEGORIZED':
        return Icons.more_horiz;
      default:
        return Icons.label;
    }
  }
}
