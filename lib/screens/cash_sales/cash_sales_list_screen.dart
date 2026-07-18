import 'package:flutter/material.dart';

import '../../models/cash_sale.dart';
import '../../repositories/cash_sales_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import 'cash_sale_details_screen.dart';
import 'cash_sale_form_screen.dart';

class CashSalesListScreen extends StatefulWidget {
  const CashSalesListScreen({super.key});

  @override
  State<CashSalesListScreen> createState() => _CashSalesListScreenState();
}

class _CashSalesListScreenState extends State<CashSalesListScreen> {
  final _searchController = TextEditingController();
  List<CashSale> _sales = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'All';

  bool get _canManageErp {
    final role = AuthService.instance.cachedProfile?.role;
    return role == 'owner' || role == 'coordinator';
  }

  bool get _canCreateCashInvoice {
    final role = AuthService.instance.cachedProfile?.role;
    return role == 'owner' || role == 'employee';
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await CashSalesRepository.instance.getSales();
      if (!mounted) return;
      setState(() {
        _sales = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Cash sales could not be loaded. Please try again.';
        _loading = false;
      });
    }
  }

  List<CashSale> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    return _sales.where((sale) {
      final statusMatches = _filter == 'All' || sale.status == _filter;
      if (!statusMatches) return false;
      return query.isEmpty ||
          sale.customerName.toLowerCase().contains(query) ||
          sale.saleNumber.toLowerCase().contains(query) ||
          sale.salesPersonName.toLowerCase().contains(query);
    }).toList();
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

  String _date(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  Future<void> _newSale() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const CashSaleFormScreen()),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _open(CashSale sale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CashSaleDetailsScreen(cashSaleId: sale.id),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _markErp(CashSale sale) async {
    if (!_canManageErp || sale.isEnteredIntoErp) return;
    try {
      await CashSalesRepository.instance.markEnteredIntoErp(sale.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${sale.saleNumber} entered into ERP.')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The ERP status could not be updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      floatingActionButton: !_canCreateCashInvoice
          ? null
          : FloatingActionButton.extended(
        onPressed: _newSale,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New Cash Invoice',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 1000 ? 32.0 : 16.0;
            return RefreshIndicator(
              onRefresh: _load,
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
                                _header(),
                                const SizedBox(height: 20),
                              ],
                              _statistics(),
                              const SizedBox(height: 18),
                              _toolbar(),
                              const SizedBox(height: 14),
                              _content(constraints.maxWidth),
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

  Widget _header() {
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
              'Cash Sales',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 4),
            Text(
              'Completed sales tickets and ERP posting control',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _statistics() {
    final enteredIntoErp =
        _sales.where((sale) => sale.isEnteredIntoErp).length;
    final pending = _sales.where((sale) => !sale.isEnteredIntoErp).length;
    final total = _sales.fold<double>(0, (sum, sale) => sum + sale.grandTotal);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _StatCard(
            title: 'Total Sales Tickets',
            value: _sales.length.toString(),
            icon: Icons.receipt_long_outlined,
            color: AppColors.primary,
          ),
          _StatCard(
            title: 'Total Entered in ERP',
            value: enteredIntoErp.toString(),
            icon: Icons.account_balance_outlined,
            color: const Color(0xFF2563EB),
          ),
          _StatCard(
            title: 'Pending Tickets',
            value: pending.toString(),
            icon: Icons.pending_actions_outlined,
            color: const Color(0xFFE18422),
          ),
          _StatCard(
            title: 'Total Sales Value',
            value: 'PKR ${_money(total)}',
            icon: Icons.payments_outlined,
            color: const Color(0xFF16845B),
          ),
        ];
        if (constraints.maxWidth >= 780) {
          return Row(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                Expanded(child: cards[index]),
                if (index != cards.length - 1) const SizedBox(width: 10),
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
              width: 150,
              child: cards[index],
            ),
          ),
        );
      },
    );
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = SizedBox(
            height: 48,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search customer, ticket or sales person',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
          );
          final filters = SizedBox(
            height: 48,
            child: _CashSalesFilter(
              value: _filter,
              onChanged: (value) => setState(() => _filter = value),
            ),
          );
          if (constraints.maxWidth < 760) {
            return Column(
              children: [
                search,
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: filters),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 20),
              SizedBox(width: 480, child: filters),
            ],
          );
        },
      ),
    );
  }

  Widget _content(double screenWidth) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(70),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _MessagePanel(
        icon: Icons.cloud_off_outlined,
        message: _error!,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }
    if (_filtered.isEmpty) {
      return const _MessagePanel(
        icon: Icons.receipt_long_outlined,
        message: 'No cash sales match the current filter.',
      );
    }
    if (screenWidth >= 850) return _desktopTable();
    return Column(
      children: _filtered
          .map(
            (sale) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _mobileCard(sale),
            ),
          )
          .toList(),
    );
  }

  Widget _desktopTable() {
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
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                horizontalMargin: 14,
                columnSpacing: 18,
                dataRowMinHeight: 62,
                dataRowMaxHeight: 68,
                headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
                headingTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                columns: const [
                  DataColumn(label: SizedBox(width: 145, child: Text('Customer Name'))),
                  DataColumn(label: SizedBox(width: 112, child: Text('Sales Ticket'))),
                  DataColumn(label: SizedBox(width: 105, child: Text('Sales Person'))),
                  DataColumn(label: SizedBox(width: 78, child: Text('Date'))),
                  DataColumn(label: SizedBox(width: 98, child: Text('Grand Total')), numeric: true),
                  DataColumn(label: SizedBox(width: 112, child: Text('Status'))),
                  DataColumn(label: SizedBox(width: 92, child: Text('Action'))),
                ],
                rows: _filtered.map((sale) {
                  return DataRow(
                    onSelectChanged: (_) => _open(sale),
                    cells: [
                      DataCell(SizedBox(
                        width: 145,
                        child: Text(
                          sale.customerName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      )),
                      DataCell(SizedBox(
                        width: 112,
                        child: Text(sale.saleNumber, overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(SizedBox(
                        width: 105,
                        child: Text(
                          sale.salesPersonName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                      DataCell(SizedBox(width: 78, child: Text(_date(sale.createdAt)))),
                      DataCell(SizedBox(
                        width: 98,
                        child: Text(
                          'PKR ${_money(sale.grandTotal)}',
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      )),
                      DataCell(SizedBox(
                        width: 112,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _StatusChip(status: sale.status),
                        ),
                      )),
                      DataCell(SizedBox(
                        width: 92,
                        child: sale.isEnteredIntoErp
                            ? const Align(
                                alignment: Alignment.centerLeft,
                                child: Icon(Icons.verified_rounded, color: Color(0xFF2563EB)),
                              )
                            : _canManageErp
                                ? FilledButton.tonal(
                                    onPressed: () => _markErp(sale),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(92, 34),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Enter in ERP',
                                        style: TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    onPressed: () => _open(sale),
                                    icon: const Icon(Icons.visibility_outlined),
                                  ),
                              )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mobileCard(CashSale sale) {
    return InkWell(
      onTap: () => _open(sale),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sale.customerName,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusChip(status: sale.status),
              ],
            ),
            const SizedBox(height: 8),
            Text('${sale.saleNumber} • ${_date(sale.createdAt)}'),
            const SizedBox(height: 5),
            Text('Sales Person: ${sale.salesPersonName}'),
            const SizedBox(height: 10),
            Text(
              'PKR ${_money(sale.grandTotal)}',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (_canManageErp && !sale.isEnteredIntoErp) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => _markErp(sale),
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Entered into ERP'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final erp = status == 'Entered into ERP';
    final color = erp ? const Color(0xFF2563EB) : const Color(0xFF16845B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CashSalesFilter extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CashSalesFilter({
    required this.value,
    required this.onChanged,
  });

  static const _options = ['All', 'Completed', 'Entered into ERP'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF64748B)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              for (var index = 0; index < _options.length; index++)
                Expanded(
                  child: _FilterOption(
                    label: _options[index],
                    selected: value == _options[index],
                    showDivider: index < _options.length - 1,
                    onTap: () => onChanged(_options[index]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterOption extends StatelessWidget {
  final String label;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  const _FilterOption({
    required this.label,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(
                    right: BorderSide(color: Color(0xFF94A3B8)),
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF334155),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

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
        boxShadow: const [
          BoxShadow(color: Color(0x0D0F172A), blurRadius: 16, offset: Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: mobile ? 34 : 42,
            height: mobile ? 34 : 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: mobile ? 18 : 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: mobile ? 17 : 21,
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
}

class _MessagePanel extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const _MessagePanel({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 52, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
