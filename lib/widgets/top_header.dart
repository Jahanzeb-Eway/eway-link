import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/attendance_notification.dart';
import '../repositories/attendance_notification_repository.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class TopHeader extends StatefulWidget {
  final String pageTitle;
  final VoidCallback? onMenuPressed;

  const TopHeader({
    super.key,
    required this.pageTitle,
    this.onMenuPressed,
  });

  @override
  State<TopHeader> createState() => _TopHeaderState();
}

class _TopHeaderState extends State<TopHeader> {
  AppUser? _profile;

  @override
  void initState() {
    super.initState();
    _profile = AuthService.instance.cachedProfile;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.instance.loadCurrentProfile();
    if (mounted) setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final fullName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Employee';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Container(
          height: compact ? 64 : 80,
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 30),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE8ECF3)),
            ),
          ),
          child: Row(
            children: [
              if (widget.onMenuPressed != null) ...[
                IconButton(
                  tooltip: 'Open navigation',
                  onPressed: widget.onMenuPressed,
                  icon: const Icon(Icons.menu_rounded),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  widget.pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 21 : 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (profile?.isOwner == true) ...[
                _NotificationBell(compact: compact),
                SizedBox(width: compact ? 10 : 20),
              ],
              CircleAvatar(
                radius: compact ? 19 : 22,
                backgroundColor: AppColors.primary,
                child: Text(
                  _initials(fullName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _roleLabel(profile?.role ?? 'employee'),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'E';
    if (words.length == 1) return words.first[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  String _roleLabel(String value) {
    if (value.isEmpty) return 'Employee';
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }
}

class _NotificationBell extends StatelessWidget {
  final bool compact;

  const _NotificationBell({required this.compact});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AttendanceNotification>>(
      stream: AttendanceNotificationRepository.instance.watch(),
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? const <AttendanceNotification>[];
        final unread = notifications.where((item) => !item.isRead).length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openNotificationCenter(context),
                child: SizedBox(
                  width: compact ? 40 : 42,
                  height: compact ? 40 : 42,
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: -5,
                top: -6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCF3E4F),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : unread.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openNotificationCenter(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NotificationCenterSheet(),
    );
  }
}

class _NotificationCenterSheet extends StatelessWidget {
  const _NotificationCenterSheet();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: height.clamp(420.0, 760.0).toDouble(),
        width: 720,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Owner Notifications',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Live attendance activity',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: AttendanceNotificationRepository
                        .instance
                        .markAllRead,
                    child: const Text('Mark all read'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<AttendanceNotification>>(
                stream: AttendanceNotificationRepository.instance.watch(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const _NotificationMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Notifications unavailable',
                      message: 'Check the connection and try again.',
                    );
                  }

                  final notifications =
                      snapshot.data ?? const <AttendanceNotification>[];
                  if (notifications.isEmpty) {
                    return const _NotificationMessage(
                      icon: Icons.notifications_none_rounded,
                      title: 'No notifications yet',
                      message:
                          'Employee check-in and checkout alerts will appear here.',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _NotificationTile(notification: notifications[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AttendanceNotification notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final color = notification.isCheckIn
        ? const Color(0xFF16845B)
        : notification.isCheckOut
        ? const Color(0xFF6B5DD3)
        : AppColors.primary;
    final icon = notification.isCheckIn
        ? Icons.login_rounded
        : notification.isCheckOut
        ? Icons.logout_rounded
        : Icons.notifications_active_outlined;

    return Material(
      color: notification.isRead
          ? Colors.white
          : const Color(0xFFF0F8FC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: notification.isRead
            ? null
            : () => AttendanceNotificationRepository.instance.markRead(
                notification.id,
              ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: notification.isRead
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFFB9DCEC),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _formatDateTime(notification.occurredAt),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}  '
        '$hour:${value.minute.toString().padLeft(2, '0')} $period';
  }
}

class _NotificationMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _NotificationMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
