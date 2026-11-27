import 'app_icons.dart';
import 'package:flutter/material.dart';

class CategoryStyle {
  CategoryStyle._();

  static IconData iconForCode(String? code) {
    switch ((code ?? '').trim().toUpperCase()) {
      case 'FOOD':
        return AppIcons.utensils;
      case 'CLOTHING':
        return AppIcons.shirt;
      case 'TRANSPORT':
        return AppIcons.car;
      case 'UTILITIES':
        return AppIcons.zap;
      case 'HEALTH':
        return AppIcons.heart;
      case 'ENTERTAINMENT':
        return AppIcons.clapperboard;
      case 'HOME':
        return AppIcons.house;
      case 'ELECTRONICS':
        return AppIcons.monitorSmartphone;
      case 'EDUCATION':
        return AppIcons.graduationCap;
      case 'PERSONAL_CARE':
        return AppIcons.leaf;
      case 'FLOWERS':
        return AppIcons.flower2;
      case 'OTHER':
      case 'UNCATEGORIZED':
        return AppIcons.ellipsis;
      default:
        return AppIcons.shoppingBag;
    }
  }
}
