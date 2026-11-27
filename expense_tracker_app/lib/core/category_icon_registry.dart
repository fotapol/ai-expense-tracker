import 'app_icons.dart';
import 'package:flutter/material.dart';

class CategoryIconOption {
  const CategoryIconOption({required this.key, required this.icon});

  final String key;
  final IconData icon;
}

class CategoryIconRegistry {
  CategoryIconRegistry._();

  static const List<CategoryIconOption> options = [
    CategoryIconOption(key: 'restaurant', icon: AppIcons.utensils),
    CategoryIconOption(key: 'car', icon: AppIcons.car),
    CategoryIconOption(key: 'bag', icon: AppIcons.shoppingBag),
    CategoryIconOption(key: 'movie', icon: AppIcons.clapperboard),
    CategoryIconOption(key: 'health', icon: AppIcons.heartPulse),
    CategoryIconOption(key: 'bolt', icon: AppIcons.zap),
    CategoryIconOption(key: 'school', icon: AppIcons.graduationCap),
    CategoryIconOption(key: 'shirt', icon: AppIcons.shirt),
    CategoryIconOption(key: 'devices', icon: AppIcons.monitorSmartphone),
    CategoryIconOption(key: 'home', icon: AppIcons.house),
    CategoryIconOption(key: 'flight', icon: AppIcons.plane),
    CategoryIconOption(key: 'gift', icon: AppIcons.gift),
    CategoryIconOption(key: 'shield', icon: AppIcons.shield),
    CategoryIconOption(key: 'sparkle', icon: AppIcons.sparkles),
    CategoryIconOption(key: 'pets', icon: AppIcons.pawPrint),
    CategoryIconOption(key: 'work', icon: AppIcons.briefcaseBusiness),
    CategoryIconOption(key: 'cafe', icon: AppIcons.coffee),
    CategoryIconOption(key: 'fitness', icon: AppIcons.dumbbell),
    CategoryIconOption(key: 'beauty', icon: AppIcons.accessibility),
    CategoryIconOption(key: 'tag', icon: AppIcons.tag),
  ];

  static IconData resolve(String? iconKey, {String? code}) {
    final normalizedIcon = (iconKey ?? '').trim().toLowerCase();
    for (final option in options) {
      if (option.key == normalizedIcon) {
        return option.icon;
      }
    }

    switch ((code ?? '').trim().toUpperCase()) {
      case 'FOOD':
        return AppIcons.utensils;
      case 'TRANSPORT':
        return AppIcons.car;
      case 'SHOPPING':
      case 'CLOTHING':
        return AppIcons.shoppingBag;
      case 'ENTERTAINMENT':
        return AppIcons.clapperboard;
      case 'HEALTH':
        return AppIcons.heartPulse;
      case 'UTILITIES':
        return AppIcons.zap;
      case 'EDUCATION':
        return AppIcons.graduationCap;
      case 'ELECTRONICS':
        return AppIcons.monitorSmartphone;
      case 'HOME':
        return AppIcons.house;
      case 'TRAVEL':
        return AppIcons.plane;
      case 'GIFTS':
      case 'GIFTS_DONATIONS':
        return AppIcons.gift;
      case 'INSURANCE':
        return AppIcons.shield;
      case 'PERSONAL_CARE':
        return AppIcons.accessibility;
      default:
        return AppIcons.tag;
    }
  }
}
