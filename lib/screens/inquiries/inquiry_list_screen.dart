import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_colors.dart';
import 'inquiry_details_screen.dart';
import 'inquiry_form_screen.dart';
import 'inquiry_pricing_screen.dart';

class InquiryListScreen extends StatefulWidget {
  const InquiryListScreen({super.key});

  @override
  State<InquiryListScreen> createState() => _InquiryListScreenState();
}

class _InquiryListScreenState extends State<InquiryListScreen> {
  final _db = SupabaseService.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _inquiries = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'All';

  bool get _canCreateInquiry {
    final role = AuthService.instance.cachedProfile?.role;
    return role == 'owner' || role == 'coordinator';
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshView);
    _loadInquiries();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshView)
      ..dispose();
    super.dispose();
  }

  void _refreshView() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInquiries() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await _db.from('inquiries').select('''
        id,
        inquiry_no,
        coordinator,
        coordinator_id,
        created_by,
        due_date,
        status,
        grand_total,
        created_at,
        customers(
          customer_name
        )
      ''').order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _inquiries = List<Map<String, dynamic>>.from(
          (response as List).map(
            (row) => Map<String, dynamic>.from(row as Map),
          ),
        );
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Inquiries could not be loaded. Check your connection and try again.';
        _isLoading = false;
      });
    }
  }

  String _text(dynamic value, {String fallback = '—'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) {
    final amount = _number(value);
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

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return '—';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year}';
  }

  String _customerName(Map<String, dynamic> inquiry) {
    final relation = inquiry['customers'];
    if (relation is Map) return _text(relation['customer_name']);
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      return _text((relation.first as Map)['customer_name']);
    }
    return '—';
  }

  String _effectiveStatus(Map<String, dynamic> inquiry) {
    final status = _text(inquiry['status'], fallback: 'Pending');
    if (status.toLowerCase() == 'completed') return 'Completed';
    if (status.toLowerCase() == 'rejected') return 'Rejected';
    final dueDate = DateTime.tryParse(inquiry['due_date']?.toString() ?? '');
    if (dueDate != null) {
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final dueOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (dueOnly.isBefore(todayOnly)) return 'Overdue';
    }
    return status;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF16845B);
      case 'overdue':
        return const Color(0xFFCF3E4F);
      case 'rejected':
        return const Color(0xFF9F1239);
      default:
        return const Color(0xFFE18422);
    }
  }

  List<Map<String, dynamic>> get _filteredInquiries {
    final query = _searchController.text.trim().toLowerCase();
    return _inquiries.where((inquiry) {
      final status = _effectiveStatus(inquiry);
      final matchesStatus =
          _statusFilter == 'All' || status.toLowerCase() == _statusFilter.toLowerCase();
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;
      return _customerName(inquiry).toLowerCase().contains(query) ||
          _text(inquiry['inquiry_no']).toLowerCase().contains(query) ||
          _text(inquiry['coordinator']).toLowerCase().contains(query) ||
          status.toLowerCase().contains(query);
    }).toList();
  }

  int _count(String status) => _inquiries
      .where((inquiry) => _effectiveStatus(inquiry).toLowerCase() == status.toLowerCase())
      .length;

  bool _canEditInquiry(Map<String, dynamic> inquiry) {
    final profile = AuthService.instance.cachedProfile;
    if (profile == null) return false;
    if (profile.isOwner) return true;
    if (profile.role == 'coordinator') {
      return inquiry['created_by']?.toString() == profile.id;
    }
    if (profile.role == 'employee') {
      return true;
    }
    return false;
  }

  Future<void> _openNewInquiry() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InquiryFormScreen()),
    );
    if (mounted) await _loadInquiries();
  }

  Future<void> _openDetails(Map<String, dynamic> inquiry) async {
    final id = inquiry['id']?.toString();
    if (id == null || id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InquiryDetailsScreen(inquiryId: id),
      ),
    );
    if (mounted) await _loadInquiries();
  }

  Future<void> _editInquiry(Map<String, dynamic> inquiry) async {
    final id = inquiry['id']?.toString();
    if (id == null || id.isEmpty) return;
    final isEmployee =
        AuthService.instance.cachedProfile?.role == 'employee';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isEmployee
            ? InquiryPricingScreen(inquiryId: id)
            : InquiryFormScreen(inquiryId: id),
      ),
    );
    if (mounted) await _loadInquiries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      floatingActionButton: !_canCreateInquiry
          ? null
          : FloatingActionButton.extended(
        onPressed: _openNewInquiry,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New Inquiry',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 1000 ? 32.0 : 16.0;
            return RefreshIndicator(
              onRefresh: _loadInquiries,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      constraints.maxWidth < 700 ? 14 : 24,
                      horizontal,
                      100,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1400),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (constraints.maxWidth >= 700) ...[
                                _buildHeader(),
                                const SizedBox(height: 20),
                              ],
                              _buildStatistics(),
                              const SizedBox(height: 18),
                              _buildToolbar(),
                              const SizedBox(height: 14),
                              _buildContent(constraints.maxWidth),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Wrap(
      spacing: 16,
      runSpacing: 14,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer Inquiries',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Track customer requirements, vendor rates and due dates.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadInquiries,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _buildStatistics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _StatData('Total Inquiries', _inquiries.length, AppColors.primary, Icons.description_outlined),
          _StatData('Pending', _count('Pending'), const Color(0xFFE18422), Icons.pending_actions_outlined),
          _StatData('Completed', _count('Completed'), const Color(0xFF16845B), Icons.task_alt_rounded),
          _StatData('Overdue', _count('Overdue'), const Color(0xFFCF3E4F), Icons.notification_important_outlined),
          _StatData('Rejected', _count('Rejected'), const Color(0xFF9F1239), Icons.block_outlined),
        ];
        if (constraints.maxWidth >= 780) {
          return Row(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                Expanded(child: _StatCard(data: cards[index])),
                if (index < cards.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        }
        return SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, index) => SizedBox(
              width: 142,
              child: _StatCard(data: cards[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search customer, inquiry number or purchaser',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          );
          final filter = DropdownButtonFormField<String>(
            key: ValueKey(_statusFilter),
            initialValue: _statusFilter,
            decoration: InputDecoration(
              labelText: 'Status',
              prefixIcon: const Icon(Icons.filter_alt_outlined),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: const ['All', 'Pending', 'Completed', 'Overdue', 'Rejected']
                .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _statusFilter = value);
            },
          );
          if (constraints.maxWidth < 650) {
            return Column(
              children: [
                search,
                const SizedBox(height: 9),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: const [
                      'All',
                      'Pending',
                      'Completed',
                      'Overdue',
                      'Rejected',
                    ].length,
                    separatorBuilder: (_, _) => const SizedBox(width: 7),
                    itemBuilder: (context, index) {
                      const values = [
                        'All',
                        'Pending',
                        'Completed',
                        'Overdue',
                        'Rejected',
                      ];
                      final value = values[index];
                      return ChoiceChip(
                        label: Text(value),
                        selected: _statusFilter == value,
                        showCheckmark: value == 'All',
                        onSelected: (_) => setState(() => _statusFilter = value),
                      );
                    },
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              SizedBox(width: 190, child: filter),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(double screenWidth) {
    if (_isLoading) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return _MessagePanel(
        icon: Icons.cloud_off_rounded,
        title: 'Unable to load inquiries',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadInquiries,
      );
    }
    final records = _filteredInquiries;
    if (records.isEmpty) {
      final canCreate = _canCreateInquiry;
      return _MessagePanel(
        icon: Icons.manage_search_rounded,
        title: _inquiries.isEmpty ? 'No inquiries yet' : 'No matching inquiries',
        message: _inquiries.isEmpty
            ? canCreate
                ? 'Create the first customer inquiry to begin tracking quotations.'
                : 'No customer inquiries are currently available for vendor pricing.'
            : 'Change the search text or status filter to see more results.',
        actionLabel: _inquiries.isEmpty
            ? canCreate
                ? 'Create Inquiry'
                : 'Refresh'
            : 'Clear Filters',
        onAction: _inquiries.isEmpty
            ? canCreate
                ? _openNewInquiry
                : _loadInquiries
            : () {
                _searchController.clear();
                setState(() => _statusFilter = 'All');
              },
      );
    }
    return screenWidth >= 850 ? _buildDesktopTable(records) : _buildMobileList(records);
  }

  Widget _buildDesktopTable(List<Map<String, dynamic>> records) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(color: Color(0x0D0F172A), blurRadius: 18, offset: Offset(0, 6)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  horizontalMargin: 14,
                  columnSpacing: 18,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  dataRowMinHeight: 62,
                  dataRowMaxHeight: 68,
                  columns: const [
                    DataColumn(label: SizedBox(width: 145, child: Text('Customer Name'))),
                    DataColumn(label: SizedBox(width: 112, child: Text('Inquiry Number'))),
                    DataColumn(label: SizedBox(width: 105, child: Text('Purchaser'))),
                    DataColumn(label: SizedBox(width: 78, child: Text('Due Date'))),
                    DataColumn(label: SizedBox(width: 98, child: Text('Grand Total')), numeric: true),
                    DataColumn(label: SizedBox(width: 78, child: Text('Status'))),
                    DataColumn(label: SizedBox(width: 70, child: Text('Actions'))),
                  ],
                  rows: records.map((inquiry) {
                    final status = _effectiveStatus(inquiry);
                    return DataRow(
                      onSelectChanged: (_) => _openDetails(inquiry),
                      cells: [
                        DataCell(SizedBox(
                          width: 145,
                          child: Text(
                            _customerName(inquiry),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 112,
                          child: Text(_text(inquiry['inquiry_no']), overflow: TextOverflow.ellipsis),
                        )),
                        DataCell(SizedBox(
                          width: 105,
                          child: Text(
                            _text(inquiry['coordinator']),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                        DataCell(SizedBox(width: 78, child: Text(_date(inquiry['due_date'])))),
                        DataCell(SizedBox(
                          width: 98,
                          child: Text(
                            'PKR ${_money(inquiry['grand_total'])}',
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 78,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: _StatusChip(status: status, color: _statusColor(status)),
                            ),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 70,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'View inquiry',
                                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _openDetails(inquiry),
                                icon: const Icon(Icons.visibility_outlined, size: 20),
                              ),
                              IconButton(
                                tooltip: 'Edit inquiry',
                                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                onPressed: status == 'Completed' ||
                                        status == 'Rejected' ||
                                        !_canEditInquiry(inquiry)
                                    ? null
                                    : () => _editInquiry(inquiry),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                            ],
                          ),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileList(List<Map<String, dynamic>> records) {
    return Column(
      children: records.map((inquiry) {
        final status = _effectiveStatus(inquiry);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openDetails(inquiry),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_customerName(inquiry), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text('Inquiry ${_text(inquiry['inquiry_no'])}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StatusChip(status: status, color: _statusColor(status)),
                      ],
                    ),
                    const Divider(height: 26),
                    Wrap(
                      spacing: 20,
                      runSpacing: 10,
                      children: [
                        _MobileFact(icon: Icons.badge_outlined, label: 'Purchaser', value: _text(inquiry['coordinator'])),
                        _MobileFact(icon: Icons.event_outlined, label: 'Due Date', value: _date(inquiry['due_date'])),
                        _MobileFact(icon: Icons.payments_outlined, label: 'Grand Total', value: 'PKR ${_money(inquiry['grand_total'])}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StatData {
  final String title;
  final int value;
  final Color color;
  final IconData icon;
  const _StatData(this.title, this.value, this.color, this.icon);
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 780;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 10 : 13,
        vertical: mobile ? 9 : 15,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x0D0F172A), blurRadius: 16, offset: Offset(0, 5))],
      ),
      child: Row(
        children: [
          Container(
            width: mobile ? 34 : 42,
            height: mobile ? 34 : 42,
            decoration: BoxDecoration(color: data.color.withValues(alpha: .11), borderRadius: BorderRadius.circular(13)),
            child: Icon(data.icon, color: data.color, size: mobile ? 18 : 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.value}',
                  style: TextStyle(
                    fontSize: mobile ? 18 : 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(999)),
      child: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

class _MobileFact extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MobileFact({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}

class _MessagePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  const _MessagePanel({required this.icon, required this.title, required this.message, required this.actionLabel, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        children: [
          Icon(icon, size: 52, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 18),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
