import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';

class AppSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onLogout;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
  });

  static const _sidebarTop = Color(0xFF0B172A);
  static const _sidebarBottom = Color(0xFF102A43);
  static const _mutedText = Color(0xFF8FA8BF);
  static const _activeStart = Color(0xFF087DB8);
  static const _activeEnd = Color(0xFF0F9AD1);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 272,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_sidebarTop, _sidebarBottom],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x260B172A),
            blurRadius: 24,
            offset: Offset(8, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: -90,
              right: -100,
              child: _DecorativeGlow(
                size: 240,
                color: Color(0x1F0F9AD1),
              ),
            ),
            const Positioned(
              bottom: 80,
              left: -130,
              child: _DecorativeGlow(
                size: 260,
                color: Color(0x147AC143),
              ),
            ),
            Column(
              children: [
                _buildBrandHeader(),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    children: [
                      const _SectionLabel('WORKSPACE'),
                      const SizedBox(height: 8),
                      _menuItem(
                        icon: Icons.space_dashboard_rounded,
                        title: 'Dashboard',
                        index: 0,
                      ),
                      _menuItem(
                        icon: Icons.location_on_rounded,
                        title: 'Attendance',
                        index: 1,
                      ),
                      _menuItem(
                        icon: Icons.description_rounded,
                        title: 'Customer Inquiries',
                        index: 2,
                      ),
                      _menuItem(
                        icon: Icons.point_of_sale_rounded,
                        title: 'Cash Sales',
                        index: 3,
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('MANAGEMENT'),
                      const SizedBox(height: 8),
                      _menuItem(
                        icon: Icons.analytics_rounded,
                        title: 'Reports',
                        index: 4,
                      ),
                      if (AuthService.instance.cachedProfile?.isOwner == true)
                        _menuItem(
                          icon: Icons.manage_accounts_rounded,
                          title: 'Employees',
                          index: 5,
                        ),
                      _menuItem(
                        icon: Icons.settings_rounded,
                        title: 'Settings',
                        index: 6,
                      ),
                    ],
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 16, 14, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EWAY LINK',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Operations Suite',
                  maxLines: 1,
                  style: TextStyle(
                    color: _mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x807AC143),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String title,
    required int index,
  }) {
    final selected = selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onItemSelected(index),
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [_activeStart, _activeEnd],
                    )
                  : null,
              borderRadius: BorderRadius.circular(13),
              border: selected
                  ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                  : Border.all(color: Colors.transparent),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x40087DB8),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? Colors.white : const Color(0xFFC6D4E1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFD9E4ED),
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: selected ? 1 : 0,
                  child: Container(
                    width: 5,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 20,
                      color: Color(0xFFFF9A9A),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sign out',
                        style: TextStyle(
                          color: Color(0xFFF2F6FA),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: _mutedText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 12,
                color: _mutedText,
              ),
              SizedBox(width: 5),
              Text(
                'Secure internal workspace',
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: AppSidebar._mutedText,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DecorativeGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _DecorativeGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
