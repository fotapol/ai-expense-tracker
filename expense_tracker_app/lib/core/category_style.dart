import 'package:flutter/material.dart';

class CategoryStyle {
  CategoryStyle._();

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
        return Icons.shopping_bag;
    }
  }
}
