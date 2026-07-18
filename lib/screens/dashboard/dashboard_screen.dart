import 'package:flutter/material.dart';

import '../../repositories/attendance_repository.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/top_header.dart';
import '../attendance/attendance_screen.dart';
import '../cash_sales/cash_sale_form_screen.dart';
import '../cash_sales/cash_sales_list_screen.dart';
import '../inquiries/inquiry_details_screen.dart';
import '../inquiries/inquiry_form_screen.dart';
import '../inquiries/inquiry_list_screen.dart';
import '../employees/employee_management_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = SupabaseService.client;
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();

  int _selectedMenu = 0;
  bool _isDashboardLoading = true;
  String? _dashboardError;
  _DashboardSnapshot _snapshot = const _DashboardSnapshot.empty();

  static const _pageTitles = [
    'Home',
    'Attendance',
    'Customer Inquiries',
    'Cash Sales',
    'Reports',
    'Employees',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _isDashboardLoading = true;
        _dashboardError = null;
      });
    }

    final now = DateTime.now();
    final todayKey = _dateKey(now);
    try {
      final results = await Future.wait<dynamic>([
        _db
            .from('attendance_sessions')
            .select('id, work_date, checked_out_at')
            .eq('work_date', todayKey),
        _db.from('inquiries').select('''
          id, inquiry_no, coordinator, due_date, status, grand_total, created_at,
          customers(customer_name)
        ''').order('created_at', ascending: false).limit(100),
        _db
            .from('cash_sales')
            .select('id, status, grand_total, created_at')
            .order('created_at', ascending: false)
            .limit(100),
        _loadLeaveStatusRows(),
      ]);

      final attendanceRows = List<Map<String, dynamic>>.from(results[0] as List);
      final inquiryRows = List<Map<String, dynamic>>.from(results[1] as List);
      final saleRows = List<Map<String, dynamic>>.from(results[2] as List);
      final leaveRows = List<Map<String, dynamic>>.from(results[3] as List);

      var leavesPending = 0;
      var leavesApproved = 0;
      var leavesRejected = 0;
      for (final leave in leaveRows) {
        switch (leave['status']?.toString().trim().toLowerCase()) {
          case 'approved':
            leavesApproved++;
            break;
          case 'rejected':
            leavesRejected++;
            break;
          default:
            leavesPending++;
            break;
        }
      }

      var pendingInquiries = 0;
      var completedInquiries = 0;
      var overdueInquiries = 0;
      for (final inquiry in inquiryRows) {
        final status = _inquiryStatus(inquiry, now);
        switch (status) {
          case 'Completed':
            completedInquiries++;
            break;
          case 'Overdue':
            overdueInquiries++;
            break;
          case 'Rejected':
            break;
          default:
            pendingInquiries++;
            break;
        }
      }

      var pendingErp = 0;
      var enteredErp = 0;
      var salesToday = 0.0;
      var salesTicketsToday = 0;
      for (final sale in saleRows) {
        final status = sale['status']?.toString() ?? 'Completed';
        if (status == 'Entered into ERP') {
          enteredErp++;
        } else {
          pendingErp++;
        }
        final createdAt = DateTime.tryParse(
          sale['created_at']?.toString() ?? '',
        )?.toLocal();
        if (createdAt != null && _isSameDay(createdAt, now)) {
          salesTicketsToday++;
          salesToday += _number(sale['grand_total']);
        }
      }

      final recentInquiries = inquiryRows
          .take(5)
          .map(
            (row) => _RecentInquiry(
              id: row['id']?.toString() ?? '',
              customerName: _customerName(row),
              inquiryNumber: row['inquiry_no']?.toString() ?? '—',
              coordinator: row['coordinator']?.toString() ?? '—',
              dueDate: _parseDate(row['due_date']),
              status: _inquiryStatus(row, now),
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _snapshot = _DashboardSnapshot(
          presentToday: attendanceRows.length,
          currentlyCheckedIn: attendanceRows
              .where((row) => row['checked_out_at'] == null)
              .length,
          pendingInquiries: pendingInquiries,
          completedInquiries: completedInquiries,
          overdueInquiries: overdueInquiries,
          totalInquiries: inquiryRows.length,
          pendingErp: pendingErp,
          enteredErp: enteredErp,
          totalSalesTickets: saleRows.length,
          salesTicketsToday: salesTicketsToday,
          salesToday: salesToday,
          leavesPending: leavesPending,
          leavesApproved: leavesApproved,
          leavesRejected: leavesRejected,
          recentInquiries: recentInquiries,
        );
        _isDashboardLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dashboardError =
            'Dashboard information could not be refreshed. Check the connection and try again.';
        _isDashboardLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadLeaveStatusRows() async {
    try {
      final rows = await _db
          .from('leave_requests')
          .select('id, status')
          .eq('leave_year', DateTime.now().year);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _parseDate(dynamic value) {
    return DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String _customerName(Map<String, dynamic> inquiry) {
    final relation = inquiry['customers'];
    if (relation is Map) {
      return relation['customer_name']?.toString().trim().isNotEmpty == true
          ? relation['customer_name'].toString().trim()
          : '—';
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      final value = (relation.first as Map)['customer_name']?.toString().trim();
      return value?.isNotEmpty == true ? value! : '—';
    }
    return '—';
  }

  String _inquiryStatus(Map<String, dynamic> inquiry, DateTime now) {
    final stored = inquiry['status']?.toString().trim() ?? 'Pending';
    if (stored.toLowerCase() == 'completed') return 'Completed';
    if (stored.toLowerCase() == 'rejected') return 'Rejected';
    final dueDate = _parseDate(inquiry['due_date']);
    if (dueDate != null) {
      final today = DateTime(now.year, now.month, now.day);
      final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (due.isBefore(today)) return 'Overdue';
    }
    return stored.isEmpty ? 'Pending' : stored;
  }

  String _money(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final digits = parts.first;
    final output = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      final remaining = digits.length - index;
      output.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) output.write(',');
    }
    return '${output.toString()}.${parts.last}';
  }

  String _shortDate(DateTime? value) {
    if (value == null) return '—';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  Widget _currentPage() {
    switch (_selectedMenu) {
      case 0:
        return _homePage();
      case 1:
        return const AttendanceScreen();
      case 2:
        return const InquiryListScreen();
      case 3:
        return const CashSalesListScreen();
      case 4:
        return const _ComingSoonPanel(
          icon: Icons.analytics_outlined,
          title: 'Reports',
          message: 'Operational and management reporting is coming next.',
        );
      case 5:
        return const EmployeeManagementScreen();
      case 6:
        return const _ComingSoonPanel(
          icon: Icons.settings_outlined,
          title: 'Settings',
          message: 'Company and workflow settings are being prepared.',
        );
      default:
        return _homePage();
    }
  }

  Future<void> _openNewInquiry() async {
    final role = AuthService.instance.cachedProfile?.role;
    if (role != 'owner' && role != 'coordinator') return;
    if (!await _ensureAttendance()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InquiryFormScreen()),
    );
    if (mounted) await _loadDashboard();
  }

  Future<void> _openNewCashSale() async {
    final role = AuthService.instance.cachedProfile?.role;
    if (role != 'owner' && role != 'employee') return;
    if (!await _ensureAttendance()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CashSaleFormScreen()),
    );
    if (mounted) await _loadDashboard();
  }

  Future<void> _openInquiry(_RecentInquiry inquiry) async {
    if (inquiry.id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InquiryDetailsScreen(inquiryId: inquiry.id),
      ),
    );
    if (mounted) await _loadDashboard();
  }

  Future<bool> _ensureAttendance() async {
    final profile = AuthService.instance.cachedProfile;
    if (profile?.isOwner == true) return true;
    if (profile == null) return false;
    try {
      if (await AttendanceRepository.instance.hasOperationalAccessToday()) {
        return true;
      }
    } catch (_) {}
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Check in to Attendance before accessing operational work.'),
      ),
    );
    setState(() => _selectedMenu = 1);
    return false;
  }

  Future<void> _selectMenu(int index) async {
    final profile = AuthService.instance.cachedProfile;
    final requiresDailyAttendance = profile?.isOwner != true && index > 1;
    if (requiresDailyAttendance && !await _ensureAttendance()) return;
    if (!mounted) return;
    setState(() => _selectedMenu = index);
    if (index == 0) _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 850;
        final page = Column(
          children: [
            TopHeader(
              pageTitle: _pageTitles[_selectedMenu],
              onMenuPressed: mobile
                  ? () => _mobileScaffoldKey.currentState?.openDrawer()
                  : null,
            ),
            Expanded(child: _currentPage()),
          ],
        );

        if (mobile) {
          return Scaffold(
            key: _mobileScaffoldKey,
            backgroundColor: const Color(0xFFF4F6F9),
            drawer: Drawer(
              width: 272,
              child: AppSidebar(
                selectedIndex: _selectedMenu,
                onItemSelected: (index) async {
                  _mobileScaffoldKey.currentState?.closeDrawer();
                  await _selectMenu(index);
                },
                onLogout: () async {
                  _mobileScaffoldKey.currentState?.closeDrawer();
                  await AuthService.instance.signOut();
                },
              ),
            ),
            body: SafeArea(bottom: false, child: page),
            bottomNavigationBar: NavigationBar(
              height: 68,
              selectedIndex: _mobileNavigationIndex(),
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              onDestinationSelected: (index) async {
                if (index == 4) {
                  _mobileScaffoldKey.currentState?.openDrawer();
                  return;
                }
                const menuIndexes = [0, 2, 3, 1];
                await _selectMenu(menuIndexes[index]);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  selectedIcon: Icon(Icons.description_rounded),
                  label: 'Inquiries',
                ),
                NavigationDestination(
                  icon: Icon(Icons.point_of_sale_outlined),
                  selectedIcon: Icon(Icons.point_of_sale_rounded),
                  label: 'Cash Sales',
                ),
                NavigationDestination(
                  icon: Icon(Icons.location_on_outlined),
                  selectedIcon: Icon(Icons.location_on_rounded),
                  label: 'Attendance',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz_rounded),
                  label: 'More',
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF4F6F9),
          body: Row(
            children: [
              AppSidebar(
                selectedIndex: _selectedMenu,
                onItemSelected: _selectMenu,
                onLogout: () async {
                  await AuthService.instance.signOut();
                },
              ),
              Expanded(child: page),
            ],
          ),
        );
      },
    );
  }

  int _mobileNavigationIndex() {
    if (_selectedMenu == 0) return 0;
    if (_selectedMenu == 2) return 1;
    if (_selectedMenu == 3) return 2;
    if (_selectedMenu == 1) return 3;
    return 4;
  }

  Widget _homePage() {
    final profile = AuthService.instance.cachedProfile;
    final name = profile?.fullName.trim() ?? '';
    final firstName = name.isEmpty ? 'there' : name.split(RegExp(r'\s+')).first;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 1000 ? 32.0 : 18.0;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 40),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DashboardHeading(
                            firstName: firstName,
                            isLoading: _isDashboardLoading,
                            onRefresh: _loadDashboard,
                          ),
                          if (_dashboardError != null) ...[
                            const SizedBox(height: 16),
                            _DashboardError(
                              message: _dashboardError!,
                              onRetry: _loadDashboard,
                            ),
                          ],
                          const SizedBox(height: 20),
                          _buildMetrics(),
                          const SizedBox(height: 18),
                          _buildQuickActions(),
                          const SizedBox(height: 18),
                          _buildOperationalPanels(constraints.maxWidth),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetrics() {
    final role = AuthService.instance.cachedProfile?.role ?? 'employee';
    final metrics = [
      if (role == 'owner')
        _MetricData(
          label: 'Present Today',
          value: '${_snapshot.presentToday}',
          detail: '${_snapshot.currentlyCheckedIn} currently checked in',
          icon: Icons.badge_outlined,
          color: const Color(0xFF16845B),
        ),
      _MetricData(
        label: 'Pending Inquiries',
        value: '${_snapshot.pendingInquiries}',
        detail: '${_snapshot.completedInquiries} completed',
        icon: Icons.description_outlined,
        color: const Color(0xFFE18422),
      ),
      _MetricData(
        label: 'Overdue Inquiries',
        value: '${_snapshot.overdueInquiries}',
        detail: _snapshot.overdueInquiries == 0
            ? 'No overdue follow-up'
            : 'Follow-up required',
        icon: Icons.notification_important_outlined,
        color: const Color(0xFFCF3E4F),
      ),
      if (role != 'employee')
        _MetricData(
          label: 'Pending ERP Entry',
          value: '${_snapshot.pendingErp}',
          detail: '${_snapshot.enteredErp} tickets entered',
          icon: Icons.account_balance_outlined,
          color: const Color(0xFF2563EB),
        ),
      _MetricData(
        label: 'Sales Today',
        value: 'PKR ${_money(_snapshot.salesToday)}',
        detail: '${_snapshot.salesTicketsToday} sales tickets',
        icon: Icons.payments_outlined,
        color: AppColors.primary,
      ),
      _MetricData(
        label: 'Leaves to be Approved',
        value: '${_snapshot.leavesPending}',
        detail: 'Awaiting owner decision',
        icon: Icons.pending_actions_outlined,
        color: const Color(0xFFE18422),
      ),
      _MetricData(
        label: 'Leaves Approved',
        value: '${_snapshot.leavesApproved}',
        detail: 'Approved requests',
        icon: Icons.event_available_outlined,
        color: const Color(0xFF16845B),
      ),
      _MetricData(
        label: 'Leaves Rejected',
        value: '${_snapshot.leavesRejected}',
        detail: 'Rejected requests',
        icon: Icons.event_busy_outlined,
        color: const Color(0xFFCF3E4F),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: metrics.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => SizedBox(
                width: 154,
                child: _MetricCard(data: metrics[index]),
              ),
            ),
          );
        }
        final columns = constraints.maxWidth >= 980
            ? 8
            : constraints.maxWidth >= 680
                ? 3
                : constraints.maxWidth >= 320
                    ? 2
                    : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: _MetricCard(data: metric),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    final role = AuthService.instance.cachedProfile?.role;
    final actions = [
      if (role == 'owner' || role == 'coordinator')
        _QuickActionData(
          label: 'New Inquiry',
          icon: Icons.note_add_rounded,
          onTap: _openNewInquiry,
        ),
      if (role == 'owner' || role == 'employee')
        _QuickActionData(
          label: 'New Cash Invoice',
          icon: Icons.point_of_sale_outlined,
          onTap: _openNewCashSale,
        ),
      _QuickActionData(
        label: 'Attendance',
        icon: Icons.location_on_outlined,
        onTap: () => _selectMenu(1),
      ),
      _QuickActionData(
        label: 'All Inquiries',
        icon: Icons.list_alt_rounded,
        onTap: () => _selectMenu(2),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actions
                .map(
                  (action) => SizedBox(
                    width: constraints.maxWidth >= 720
                        ? (constraints.maxWidth - 30) / 4
                        : (constraints.maxWidth - 10) / 2,
                    child: _QuickAction(data: action),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildOperationalPanels(double screenWidth) {
    final recent = _RecentInquiriesPanel(
      inquiries: _snapshot.recentInquiries,
      formatDate: _shortDate,
      onOpen: _openInquiry,
      onViewAll: () => _selectMenu(2),
    );
    final workflow = _WorkflowPanel(snapshot: _snapshot);
    if (screenWidth < 900) {
      return Column(
        children: [
          recent,
          const SizedBox(height: 18),
          workflow,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 7, child: recent),
        const SizedBox(width: 18),
        Expanded(flex: 3, child: workflow),
      ],
    );
  }
}

class _DashboardSnapshot {
  final int presentToday;
  final int currentlyCheckedIn;
  final int pendingInquiries;
  final int completedInquiries;
  final int overdueInquiries;
  final int totalInquiries;
  final int pendingErp;
  final int enteredErp;
  final int totalSalesTickets;
  final int salesTicketsToday;
  final double salesToday;
  final int leavesPending;
  final int leavesApproved;
  final int leavesRejected;
  final List<_RecentInquiry> recentInquiries;

  const _DashboardSnapshot({
    required this.presentToday,
    required this.currentlyCheckedIn,
    required this.pendingInquiries,
    required this.completedInquiries,
    required this.overdueInquiries,
    required this.totalInquiries,
    required this.pendingErp,
    required this.enteredErp,
    required this.totalSalesTickets,
    required this.salesTicketsToday,
    required this.salesToday,
    required this.leavesPending,
    required this.leavesApproved,
    required this.leavesRejected,
    required this.recentInquiries,
  });

  const _DashboardSnapshot.empty()
      : presentToday = 0,
        currentlyCheckedIn = 0,
        pendingInquiries = 0,
        completedInquiries = 0,
        overdueInquiries = 0,
        totalInquiries = 0,
        pendingErp = 0,
        enteredErp = 0,
        totalSalesTickets = 0,
        salesTicketsToday = 0,
        salesToday = 0,
        leavesPending = 0,
        leavesApproved = 0,
        leavesRejected = 0,
        recentInquiries = const [];
}

class _RecentInquiry {
  final String id;
  final String customerName;
  final String inquiryNumber;
  final String coordinator;
  final DateTime? dueDate;
  final String status;

  const _RecentInquiry({
    required this.id,
    required this.customerName,
    required this.inquiryNumber,
    required this.coordinator,
    required this.dueDate,
    required this.status,
  });
}

class _MetricData {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  const _MetricData({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;

  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 680;
    if (mobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(data.icon, color: data.color, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      data.value,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 116,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: data.color, size: 16),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHeading extends StatelessWidget {
  final String firstName;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const _DashboardHeading({
    required this.firstName,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good day, $firstName',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Operations overview',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: isLoading ? null : onRefresh,
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(isLoading ? 'Refreshing' : 'Refresh'),
        ),
      ],
    );
  }
}

class _DashboardError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _DashboardError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: Color(0xFFBE123C), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF9F1239), fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _QuickActionData {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionData({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _QuickAction extends StatelessWidget {
  final _QuickActionData data;

  const _QuickAction({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Icon(data.icon, size: 19, color: AppColors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  data.label,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentInquiriesPanel extends StatelessWidget {
  final List<_RecentInquiry> inquiries;
  final String Function(DateTime? value) formatDate;
  final Future<void> Function(_RecentInquiry inquiry) onOpen;
  final VoidCallback onViewAll;

  const _RecentInquiriesPanel({
    required this.inquiries,
    required this.formatDate,
    required this.onOpen,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return _DashboardPanel(
      title: 'Recent inquiries',
      subtitle: 'Latest customer requirements and workflow status',
      trailing: TextButton(onPressed: onViewAll, child: const Text('View all')),
      child: inquiries.isEmpty
          ? const _PanelEmptyState(
              icon: Icons.description_outlined,
              message: 'No inquiry activity is available yet.',
            )
          : Column(
              children: [
                if (!mobile) const _RecentInquiryHeader(),
                for (final inquiry in inquiries)
                  if (mobile)
                    _RecentInquiryMobileRow(
                      inquiry: inquiry,
                      dueDate: formatDate(inquiry.dueDate),
                      onTap: () => onOpen(inquiry),
                    )
                  else
                    _RecentInquiryRow(
                      inquiry: inquiry,
                      dueDate: formatDate(inquiry.dueDate),
                      onTap: () => onOpen(inquiry),
                    ),
              ],
            ),
    );
  }
}

class _RecentInquiryMobileRow extends StatelessWidget {
  final _RecentInquiry inquiry;
  final String dueDate;
  final VoidCallback onTap;

  const _RecentInquiryMobileRow({
    required this.inquiry,
    required this.dueDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = inquiry.status == 'Completed'
        ? const Color(0xFF16845B)
        : inquiry.status == 'Overdue' || inquiry.status == 'Rejected'
            ? const Color(0xFFCF3E4F)
            : const Color(0xFFE18422);
    final initials = inquiry.customerName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE9EEF4))),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE8F3FA),
                foregroundColor: AppColors.primary,
                child: Text(
                  initials.isEmpty ? '—' : initials,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inquiry.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${inquiry.inquiryNumber} • ${inquiry.coordinator}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Due $dueDate',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  inquiry.status,
                  style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentInquiryHeader extends StatelessWidget {
  const _RecentInquiryHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: .35,
    );
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 8, 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('CUSTOMER', style: style)),
          Expanded(flex: 2, child: Text('INQUIRY', style: style)),
          Expanded(flex: 2, child: Text('DUE DATE', style: style)),
          SizedBox(width: 96, child: Text('STATUS', style: style)),
          SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _RecentInquiryRow extends StatelessWidget {
  final _RecentInquiry inquiry;
  final String dueDate;
  final VoidCallback onTap;

  const _RecentInquiryRow({
    required this.inquiry,
    required this.dueDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE9EEF4))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  inquiry.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  inquiry.inquiryNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  dueDate,
                  style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
                ),
              ),
              SizedBox(width: 96, child: _DashboardStatus(status: inquiry.status)),
              const SizedBox(width: 28, child: Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8))),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardStatus extends StatelessWidget {
  final String status;

  const _DashboardStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status.toLowerCase()) {
      'completed' => const Color(0xFF16845B),
      'rejected' => const Color(0xFF9F1239),
      'overdue' => const Color(0xFFCF3E4F),
      _ => const Color(0xFFE18422),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _WorkflowPanel extends StatelessWidget {
  final _DashboardSnapshot snapshot;

  const _WorkflowPanel({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final inquiryProgress = snapshot.totalInquiries == 0
        ? 0.0
        : snapshot.completedInquiries / snapshot.totalInquiries;
    final erpProgress = snapshot.totalSalesTickets == 0
        ? 0.0
        : snapshot.enteredErp / snapshot.totalSalesTickets;
    return _DashboardPanel(
      title: 'Workflow health',
      subtitle: 'Current completion across key operations',
      child: Column(
        children: [
          _ProgressItem(
            label: 'Inquiry completion',
            value: inquiryProgress,
            color: const Color(0xFF16845B),
          ),
          const SizedBox(height: 20),
          _ProgressItem(
            label: 'ERP posting',
            value: erpProgress,
            color: const Color(0xFF2563EB),
          ),
          const SizedBox(height: 20),
          _ProgressItem(
            label: 'Employees checked in',
            value: snapshot.presentToday == 0
                ? 0
                : snapshot.currentlyCheckedIn / snapshot.presentToday,
            color: AppColors.primary,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF64748B)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    snapshot.overdueInquiries == 0
                        ? 'Inquiry follow-up is currently on track.'
                        : '${snapshot.overdueInquiries} overdue inquiries need attention.',
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressItem extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _ProgressItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0.0, 1.0).toDouble();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${(safeValue * 100).round()}%',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: safeValue,
            minHeight: 7,
            backgroundColor: const Color(0xFFE8EDF3),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _DashboardPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 17),
          child,
        ],
      ),
    );
  }
}

class _PanelEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _PanelEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(icon, size: 34, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: Color(0xFF64748B))),
        ],
      ),
    );
  }
}

class _ComingSoonPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _ComingSoonPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4F6F9),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(34),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(height: 18),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
