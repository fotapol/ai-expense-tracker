import 'package:flutter/material.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Scaffold without AppBar since the top is custom
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildDailySpendingCard(context),
              const SizedBox(height: 24),
              _buildDateScroller(context),
              const SizedBox(height: 80),
              _buildEmptyState(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome,',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 4),
            const Text(
              'kirya',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: const Text('0/10', style: TextStyle(fontSize: 12)),
        )
      ],
    );
  }

  Widget _buildDailySpendingCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF4A148C), // Deep purple
            const Color(0xFF311B92), // Deeper purple
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily spending',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'RSD 0.00',
            style: TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          // Progress bar
          Stack(
            children: [
              Container(
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                height: 4,
                width: MediaQuery.of(context).size.width * 0.7, // 70% filled
                decoration: BoxDecoration(
                  color: const Color(0xFFE040FB), // Light purple
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Positioned(
                right: MediaQuery.of(context).size.width * 0.3 - 24, // Position dot at 70%
                top: -3,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEA80FC), // Neon purple dot
                    shape: BoxShape.circle,
                  ),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDateScroller(BuildContext context) {
    // Mock the date scroller
    final dates = [
      {'label': '1 Mar', 'selected': false},
      {'label': '2 Mar', 'selected': false},
      {'label': '3 Mar', 'selected': true, 'hasData': true},
      {'label': '4 Mar', 'selected': false},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: dates.map((date) {
          final isSelected = date['selected'] == true;
          final hasData = date['hasData'] == true;

          return Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF2D124D) // Dark purplish tint
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Text(
                  date['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade400,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
                if (hasData) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                ]
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        children: [
          // Icon Stack (receipt document icon)
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.receipt_long, size: 80, color: Colors.grey.shade800),
              Positioned(
                top: 10,
                child: Container(
                  width: 40,
                  height: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Positioned(
                bottom: 25,
                right: 15,
                child: Container(
                  width: 20,
                  height: 4,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'No receipts found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade300,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You haven\'t added any receipts for this\nday',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
