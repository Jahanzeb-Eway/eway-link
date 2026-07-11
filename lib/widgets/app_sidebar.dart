import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppSidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: AppColors.primary,
      child: SafeArea(
        child: Column(
          children: [

            const SizedBox(height: 20),

            // LOGO CARD
            Container(
              width: 210,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 12,
                    color: Colors.black26,
                    offset: Offset(0, 5),
                  )
                ],
              ),
              child: Image.asset(
                'assets/images/logo.png',
                height: 95,
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              "EWAY LINK",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 30),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [

                  _menuItem(Icons.dashboard, "Dashboard", 0),

                  _menuItem(Icons.location_on, "Attendance", 1),

                  _menuItem(Icons.description, "Customer Inquiries", 2),

                  _menuItem(Icons.point_of_sale, "Cash Sales", 3),

                  _menuItem(Icons.bar_chart, "Reports", 4),

                  _menuItem(Icons.event_available, "Leave", 5),

                  _menuItem(Icons.settings, "Settings", 6),
                ],
              ),
            ),

            const Divider(
              color: Colors.white24,
              thickness: 1,
              indent: 18,
              endIndent: 18,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: const Icon(
                    Icons.logout,
                    color: Colors.white,
                  ),
                  title: const Text(
                    "Logout",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {},
                ),
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    IconData icon,
    String title,
    int index,
  ) {
    final bool selected = selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 5,
      ),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: Icon(
            icon,
            color: selected ? AppColors.primary : Colors.white,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: selected ? AppColors.primary : Colors.white,
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          onTap: () => onItemSelected(index),
        ),
      ),
    );
  }
}