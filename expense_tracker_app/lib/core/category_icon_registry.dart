import 'package:flutter/material.dart';

class CategoryIconOption {
  const CategoryIconOption({required this.key, required this.icon});

  final String key;
  final IconData icon;
}

class CategoryIconRegistry {
  CategoryIconRegistry._();

  static const List<CategoryIconOption> options = [
    CategoryIconOption(key: 'restaurant', icon: Icons.restaurant_outlined),
    CategoryIconOption(key: 'car', icon: Icons.directions_car_outlined),
    CategoryIconOption(key: 'bag', icon: Icons.shopping_bag_outlined),
    CategoryIconOption(key: 'movie', icon: Icons.movie_outlined),
    CategoryIconOption(key: 'health', icon: Icons.health_and_safety_outlined),
    CategoryIconOption(key: 'bolt', icon: Icons.bolt_outlined),
    CategoryIconOption(key: 'school', icon: Icons.school_outlined),
    CategoryIconOption(key: 'shirt', icon: Icons.checkroom_outlined),
    CategoryIconOption(key: 'devices', icon: Icons.devices_outlined),
    CategoryIconOption(key: 'home', icon: Icons.house_outlined),
    CategoryIconOption(key: 'flight', icon: Icons.flight_outlined),
    CategoryIconOption(key: 'gift', icon: Icons.card_giftcard_outlined),
    CategoryIconOption(key: 'shield', icon: Icons.shield_outlined),
    CategoryIconOption(key: 'sparkle', icon: Icons.auto_awesome_outlined),
    CategoryIconOption(key: 'pets', icon: Icons.pets_outlined),
    CategoryIconOption(key: 'work', icon: Icons.work_outline),
    CategoryIconOption(key: 'cafe', icon: Icons.local_cafe_outlined),
    CategoryIconOption(key: 'fitness', icon: Icons.fitness_center_outlined),
    CategoryIconOption(key: 'beauty', icon: Icons.self_improvement_outlined),
    CategoryIconOption(key: 'tag', icon: Icons.sell_outlined),
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
        return Icons.restaurant_outlined;
      case 'TRANSPORT':
        return Icons.directions_car_outlined;
      case 'SHOPPING':
      case 'CLOTHING':
        return Icons.shopping_bag_outlined;
      case 'ENTERTAINMENT':
        return Icons.movie_outlined;
      case 'HEALTH':
        return Icons.health_and_safety_outlined;
      case 'UTILITIES':
        return Icons.bolt_outlined;
      case 'EDUCATION':
        return Icons.school_outlined;
      case 'ELECTRONICS':
        return Icons.devices_outlined;
      case 'HOME':
        return Icons.house_outlined;
      case 'TRAVEL':
        return Icons.flight_outlined;
      case 'GIFTS':
      case 'GIFTS_DONATIONS':
        return Icons.card_giftcard_outlined;
      case 'INSURANCE':
        return Icons.shield_outlined;
      case 'PERSONAL_CARE':
        return Icons.self_improvement_outlined;
      default:
        return Icons.sell_outlined;
    }
  }
}
