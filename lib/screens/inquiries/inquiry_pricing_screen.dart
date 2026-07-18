import 'package:flutter/material.dart';

import '../../repositories/inquiry_repository.dart';
import '../../repositories/vendor_repository.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_colors.dart';

class InquiryPricingScreen extends StatefulWidget {
  final String inquiryId;

  const InquiryPricingScreen({super.key, required this.inquiryId});

  @override
  State<InquiryPricingScreen> createState() => _InquiryPricingScreenState();
}

class _InquiryPricingScreenState extends State<InquiryPricingScreen> {
  final _db = SupabaseService.client;
  Map<String, dynamic>? _inquiry;
  final List<_PricingLine> _lines = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        _db.from('inquiries').select('''
          id, inquiry_no, coordinator, due_date, status, grand_total,
          customers(customer_name, address)
        ''').eq('id', widget.inquiryId).single(),
        _db.from('inquiry_items').select('''
          id, qty, previous_rate, selected_rate, total,
          items(item_name), vendors(vendor_name), units(unit_name)
        ''').eq('inquiry_id', widget.inquiryId).order('id'),
      ]);

      final inquiry = Map<String, dynamic>.from(results[0] as Map);
      final rows = List<Map<String, dynamic>>.from(
        (results[1] as List).map(
          (row) => Map<String, dynamic>.from(row as Map),
        ),
      );
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..addAll(
          rows.map(
            (row) => _PricingLine(
              id: row['id']?.toString() ?? '',
              itemName: _relationText(row, 'items', 'item_name'),
              unitName: _relationText(row, 'units', 'unit_name'),
              quantity: _number(row['qty']),
              previousRate: _number(row['previous_rate']),
              vendorName: _relationText(row, 'vendors', 'vendor_name'),
              rate: _number(row['selected_rate']),
              onChanged: _refresh,
            ),
          ),
        );
      if (!mounted) return;
      setState(() {
        _inquiry = inquiry;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This inquiry could not be loaded. Refresh and try again.';
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _save({required bool complete}) async {
    if (_saving || _inquiry == null) return;
    if (_lines.isEmpty) {
      _message('This inquiry has no items.');
      return;
    }
    for (final line in _lines) {
      if (line.vendorName.isEmpty) {
        _message('Enter a vendor for ${line.itemName}.');
        return;
      }
      if (line.rate <= 0) {
        _message('Enter a rate greater than zero for ${line.itemName}.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      for (final line in _lines) {
        final vendor = await VendorRepository.instance.getOrCreate(
          vendorName: line.vendorName,
        );
        await InquiryRepository.instance.updateInquiryItemQuote(
          inquiryItemId: line.id,
          vendorId: vendor.id,
          selectedRate: line.rate,
          total: line.total,
        );
      }
      await InquiryRepository.instance.updateInquiryPricing(
        inquiryId: widget.inquiryId,
        grandTotal: _grandTotal,
        status: complete ? 'Completed' : _status,
      );
      if (!mounted) return;
      _message(
        complete
            ? 'Vendor rates saved and inquiry completed.'
            : 'Vendor rates saved.',
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        _message('The vendor rates could not be saved. ${_friendlyError(error)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  double get _grandTotal =>
      _lines.fold(0, (total, line) => total + line.total);

  String get _status => _inquiry?['status']?.toString() ?? 'Pending';

  String get _customerName {
    final relation = _inquiry?['customers'];
    if (relation is Map) {
      return relation['customer_name']?.toString().trim() ?? 'Customer';
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      return (relation.first as Map)['customer_name']?.toString().trim() ??
          'Customer';
    }
    return 'Customer';
  }

  String get _customerAddress {
    final relation = _inquiry?['customers'];
    if (relation is Map) {
      return relation['address']?.toString().trim() ?? '—';
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      return (relation.first as Map)['address']?.toString().trim() ?? '—';
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          mobile
              ? 'Edit Vendor Rates'
              : _loading
                  ? 'Inquiry Vendor Pricing'
                  : _customerName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _loading || _saving ? null : _load,
            tooltip: 'Refresh inquiry',
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView()
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  mobile ? 10 : 20,
                  mobile ? 10 : 20,
                  mobile ? 10 : 20,
                  mobile ? 24 : 20,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _summaryCard(),
                        const SizedBox(height: 16),
                        _pricingCard(),
                        const SizedBox(height: 16),
                        _totalCard(),
                        const SizedBox(height: 20),
                        _actions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _summaryCard() {
    if (MediaQuery.sizeOf(context).width < 700) {
      return Container(
        padding: const EdgeInsets.all(13),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _compactSummaryItem('Customer Name', _customerName)),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactSummaryItem(
                    'Inquiry Number',
                    _inquiry?['inquiry_no']?.toString() ?? '—',
                  ),
                ),
              ],
            ),
            const Divider(height: 15),
            Row(
              children: [
                Expanded(
                  child: _compactSummaryItem(
                    'Purchaser',
                    _inquiry?['coordinator']?.toString() ?? '—',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactSummaryItem(
                    'Due Date',
                    _date(_inquiry?['due_date']),
                  ),
                ),
              ],
            ),
            const Divider(height: 15),
            _compactSummaryItem('Customer Address', _customerAddress),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Wrap(
        spacing: 28,
        runSpacing: 16,
        children: [
          _summaryItem('Customer Name', _customerName),
          _summaryItem(
            'Inquiry Number',
            _inquiry?['inquiry_no']?.toString() ?? '—',
          ),
          _summaryItem(
            'Purchaser',
            _inquiry?['coordinator']?.toString() ?? '—',
          ),
          _summaryItem('Due Date', _date(_inquiry?['due_date'])),
        ],
      ),
    );
  }

  Widget _compactSummaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: label == 'Customer Address' ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _summaryItem(String label, String value) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: screenWidth < 500 ? (screenWidth - 72) / 2 : 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _pricingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Row(
                children: const [
                  Icon(
                    Icons.request_quote_outlined,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vendor Rates',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              );
              const guidance = Text(
                'Only Vendor and Rate can be edited',
                style: TextStyle(color: Color(0xFF64748B)),
              );
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 8),
                    guidance,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 18),
                  guidance,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'No inquiry items are available.',
                textAlign: TextAlign.center,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 700) {
                  return Column(
                    children: _lines.asMap().entries.map((entry) {
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: entry.key == _lines.length - 1 ? 0 : 12,
                        ),
                        child: _mobilePricingCard(entry.key, entry.value),
                      );
                    }).toList(),
                  );
                }
                const minimumWidth = 1060.0;
                final width = constraints.maxWidth > minimumWidth
                    ? constraints.maxWidth
                    : minimumWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        _tableHeader(),
                        ..._lines.asMap().entries.map(
                          (entry) => _pricingRow(entry.key, entry.value),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _mobilePricingCard(int index, _PricingLine line) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE4EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Item ${index + 1}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _mobileValue('Item Name', line.itemName),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _mobileValue('Unit', line.unitName)),
              const SizedBox(width: 10),
              Expanded(
                child: _mobileValue('Quantity', _quantity(line.quantity)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: line.vendorController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Vendor',
              hintText: 'Enter vendor',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _mobileValue(
                  'Previous Rate',
                  'PKR ${_money(line.previousRate)}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: line.rateController,
                  enabled: !_saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rate',
                    hintText: '0.00',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Total: PKR ${_money(line.total)}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileValue(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFD7E0E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(value, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 42, child: _Header('#')),
          Expanded(flex: 24, child: _Header('Item Name')),
          Expanded(flex: 10, child: _Header('Unit')),
          Expanded(flex: 9, child: _Header('Qty')),
          Expanded(flex: 20, child: _Header('Vendor')),
          Expanded(flex: 13, child: _Header('Previous Rate')),
          Expanded(flex: 13, child: _Header('Rate')),
          Expanded(flex: 14, child: _Header('Total')),
        ],
      ),
    );
  }

  Widget _pricingRow(int index, _PricingLine line) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          SizedBox(width: 42, child: Text('${index + 1}')),
          Expanded(flex: 24, child: _readOnlyField(line.itemName)),
          Expanded(flex: 10, child: _readOnlyField(line.unitName)),
          Expanded(flex: 9, child: _readOnlyField(_quantity(line.quantity))),
          Expanded(
            flex: 20,
            child: _editableField(
              line.vendorController,
              hint: 'Enter vendor',
            ),
          ),
          Expanded(
            flex: 13,
            child: _readOnlyField(_money(line.previousRate)),
          ),
          Expanded(
            flex: 13,
            child: _editableField(
              line.rateController,
              numeric: true,
              hint: '0.00',
            ),
          ),
          Expanded(
            flex: 14,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'PKR ${_money(line.total)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyField(String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD7E0E8)),
        ),
        child: Text(value, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _editableField(
    TextEditingController controller, {
    bool numeric = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        enabled: !_saving,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _totalCard() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: MediaQuery.sizeOf(context).width < 500 ? double.infinity : 350,
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GRAND TOTAL',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 7),
            FittedBox(
              child: Text(
                'PKR ${_money(_grandTotal)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    final buttons = <Widget>[
          OutlinedButton.icon(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(complete: false),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Rates'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16845B),
            ),
            onPressed: _saving ? null : () => _save(complete: true),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.task_alt_rounded),
            label: const Text('Save & Complete'),
          ),
        ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buttons
                .map(
                  (button) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: SizedBox(height: 50, child: button),
                  ),
                )
                .toList(),
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: buttons
              .map(
                (button) => Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: SizedBox(width: 190, height: 48, child: button),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 52, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D0F172A),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  static String _relationText(
    Map<String, dynamic> source,
    String key,
    String field,
  ) {
    final value = source[key];
    if (value is Map) return value[field]?.toString().trim() ?? '';
    if (value is List && value.isNotEmpty && value.first is Map) {
      return (value.first as Map)[field]?.toString().trim() ?? '';
    }
    return '';
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _quantity(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  String _money(double value) => value.toStringAsFixed(2);

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '—';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year}';
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    final match = RegExp(r'message:\s*([^,}\)]+)').firstMatch(text);
    return match?.group(1)?.trim() ?? 'Please try again.';
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PricingLine {
  final String id;
  final String itemName;
  final String unitName;
  final double quantity;
  final double previousRate;
  final TextEditingController vendorController;
  final TextEditingController rateController;
  final VoidCallback onChanged;

  _PricingLine({
    required this.id,
    required this.itemName,
    required this.unitName,
    required this.quantity,
    required this.previousRate,
    required String vendorName,
    required double rate,
    required this.onChanged,
  }) : vendorController = TextEditingController(text: vendorName),
       rateController = TextEditingController(
         text: rate > 0 ? rate.toStringAsFixed(2) : '',
       ) {
    rateController.addListener(onChanged);
  }

  String get vendorName => vendorController.text.trim();
  double get rate => double.tryParse(rateController.text.trim()) ?? 0;
  double get total => quantity * rate;

  void dispose() {
    rateController.removeListener(onChanged);
    vendorController.dispose();
    rateController.dispose();
  }
}

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
