import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/cash_sale.dart';
import '../../models/customer.dart';
import '../../models/item.dart';
import '../../models/unit.dart';
import '../../repositories/cash_sales_repository.dart';
import '../../repositories/customer_repository.dart';
import '../../repositories/item_repository.dart';
import '../../repositories/unit_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';

class CashSaleFormScreen extends StatefulWidget {
  const CashSaleFormScreen({super.key});

  @override
  State<CashSaleFormScreen> createState() => _CashSaleFormScreenState();
}

class _CashSaleFormScreenState extends State<CashSaleFormScreen> {
  final _customerController = TextEditingController();
  final _addressController = TextEditingController();
  final _saleNumberController = TextEditingController();
  final List<_SaleLineEditor> _lines = [];

  List<CustomerModel> _customers = const [];
  List<ItemModel> _items = const [];
  List<UnitModel> _units = const [];
  String? _selectedCustomerId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _addLine(notify: false);
    _initialize();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _addressController.dispose();
    _saleNumberController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    final results = await Future.wait<dynamic>([
      CustomerRepository.instance.getAll().catchError(
            (_) => <CustomerModel>[],
          ),
      ItemRepository.instance.getAll().catchError(
            (_) => <ItemModel>[],
          ),
      UnitRepository.instance.getAll().catchError(
            (_) => <UnitModel>[],
          ),
      CashSalesRepository.instance.nextSaleNumber(),
      AuthService.instance.loadCurrentProfile(),
    ]);
    if (!mounted) return;
    setState(() {
      _customers = List<CustomerModel>.from(results[0] as List);
      _items = List<ItemModel>.from(results[1] as List);
      _units = List<UnitModel>.from(results[2] as List);
      _saleNumberController.text = results[3].toString();
      _loading = false;
    });
  }

  void _addLine({bool notify = true}) {
    _lines.add(
      _SaleLineEditor(
        onChanged: _refresh,
        onLookup: _lookupPreviousSale,
      ),
    );
    if (notify) _refresh();
  }

  void _removeLine(int index) {
    if (_lines.length == 1) {
      _lines.first.dispose();
      _lines[0] = _SaleLineEditor(
        onChanged: _refresh,
        onLookup: _lookupPreviousSale,
      );
    } else {
      _lines.removeAt(index).dispose();
    }
    _refresh();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  CustomerModel? _exactCustomer(String name) {
    final normalized = name.trim().toLowerCase();
    for (final customer in _customers) {
      if (customer.customerName.trim().toLowerCase() == normalized) {
        return customer;
      }
    }
    return null;
  }

  void _selectCustomer(CustomerModel customer) {
    _selectedCustomerId = customer.id;
    _customerController.text = customer.customerName;
    _addressController.text = customer.address?.trim() ?? '';
    for (final line in _lines) {
      final itemName = line.itemController.text.trim();
      if (itemName.isNotEmpty) {
        unawaited(_lookupPreviousSale(line, itemName));
      }
    }
    _refresh();
  }

  Future<void> _selectItem(_SaleLineEditor line, ItemModel item) async {
    line.itemController.text = item.itemName;
    line.cancelLookup();
    if (item.defaultUnitId != null) {
      line.unitId = item.defaultUnitId;
    }
    _refresh();
    await _lookupPreviousSale(line, item.itemName);
  }

  Future<void> _lookupPreviousSale(
    _SaleLineEditor line,
    String itemName,
  ) async {
    if (!_lines.contains(line) || itemName.trim().isEmpty) return;
    CustomerModel? customer;
    if (_selectedCustomerId == null) {
      customer = _exactCustomer(_customerController.text);
    } else {
      for (final savedCustomer in _customers) {
        if (savedCustomer.id == _selectedCustomerId) {
          customer = savedCustomer;
          break;
        }
      }
    }
    if (customer == null) {
      line.previousRateController.text = '0.00';
      line.hasHistory = false;
      _refresh();
      return;
    }

    line.isLookingUp = true;
    line.hasHistory = false;
    _refresh();
    try {
      final result = await CashSalesRepository.instance
          .getPreviousCustomerSale(
            customerId: customer.id,
            itemName: itemName,
          );
      if (!mounted || !_lines.contains(line)) return;
      if (line.itemController.text.trim().toLowerCase() !=
          itemName.trim().toLowerCase()) {
        return;
      }
      line.previousRateController.text =
          result == null ? '0.00' : result.rate.toStringAsFixed(2);
      if (result != null && result.unitName.isNotEmpty) {
        for (final unit in _units) {
          if (unit.unitName.toLowerCase() == result.unitName.toLowerCase()) {
            line.unitId = unit.id;
            break;
          }
        }
      }
      line.hasHistory = result != null;
    } catch (_) {
      line.hasHistory = false;
    } finally {
      if (mounted && _lines.contains(line)) {
        line.isLookingUp = false;
        _refresh();
      }
    }
  }

  double get _grandTotal =>
      _lines.fold<double>(0, (sum, line) => sum + line.total);

  Future<void> _save({bool enterIntoErp = false}) async {
    if (_saving) return;
    final customerName = _customerController.text.trim();
    final validLines = _lines
        .where((line) => line.itemController.text.trim().isNotEmpty)
        .toList();
    if (customerName.isEmpty) {
      _message('Customer Name is required.');
      return;
    }
    if (validLines.isEmpty) {
      _message('Add at least one sales item.');
      return;
    }
    for (final line in validLines) {
      if (line.unitId == null || line.quantity <= 0 || line.salesRate <= 0) {
        _message('Every item requires a unit, quantity and sales rate.');
        return;
      }
    }
    final profile = AuthService.instance.cachedProfile ??
        await AuthService.instance.loadCurrentProfile();
    if (profile == null) {
      _message('Your employee profile could not be loaded.');
      return;
    }

    setState(() => _saving = true);
    try {
      final customer = await CustomerRepository.instance.getOrCreate(
        customerName: customerName,
        address: _addressController.text.trim(),
      );
      final inputs = <CashSaleLineInput>[];
      for (final line in validLines) {
        final item = await ItemRepository.instance.getOrCreate(
          itemName: line.itemController.text.trim(),
          unitId: line.unitId!,
        );
        inputs.add(
          CashSaleLineInput(
            itemId: item.id,
            unitId: line.unitId!,
            quantity: line.quantity,
            previousRate: line.previousRate,
            salesRate: line.salesRate,
          ),
        );
      }
      final saleId = await CashSalesRepository.instance.createSale(
        saleNumber: _saleNumberController.text,
        customerId: customer.id,
        salesPersonName: profile.fullName,
        items: inputs,
      );
      if (enterIntoErp) {
        await CashSalesRepository.instance.markEnteredIntoErp(saleId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enterIntoErp
                ? 'Cash sale completed and entered into ERP.'
                : 'Cash sale completed successfully.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message('The cash sale could not be saved. ${error.toString()}');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
              ? 'New Cash Invoice'
              : _customerController.text.trim().isEmpty
              ? 'New Cash Sale'
              : _customerController.text.trim(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                        _headerCard(),
                        SizedBox(height: mobile ? 10 : 16),
                        _itemsCard(),
                        SizedBox(height: mobile ? 10 : 16),
                        _totalCard(),
                        SizedBox(height: mobile ? 12 : 22),
                        _actions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _headerCard() {
    final profile = AuthService.instance.cachedProfile;
    return _SalesCard(
      title: 'Customer & Sale Information',
      icon: Icons.point_of_sale_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 240
                  ? 2
                  : 1;
          final width =
              (constraints.maxWidth - ((columns - 1) * 12)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: width, child: _customerAutocomplete()),
              SizedBox(
                width: width,
                child: TextField(
                  controller: _saleNumberController,
                  readOnly: true,
                  decoration: _decoration('Sales Ticket Number', readOnly: true),
                ),
              ),
              SizedBox(
                width: width,
                child: TextFormField(
                  initialValue: profile?.fullName ?? '',
                  readOnly: true,
                  decoration: _decoration('Sales Person', readOnly: true),
                ),
              ),
              SizedBox(
                width: width,
                child: TextField(
                  controller: _addressController,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration('Customer Address'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _decoration(String label, {bool readOnly = false}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _customerAutocomplete() {
    return Autocomplete<CustomerModel>(
      displayStringForOption: (customer) => customer.customerName,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return (query.isEmpty
                ? _customers
                : _customers.where(
                    (customer) =>
                        customer.customerName.toLowerCase().contains(query),
                  ))
            .take(20);
      },
      onSelected: _selectCustomer,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) {
            _customerController.text = value;
            final exact = _exactCustomer(value);
            _selectedCustomerId = exact?.id;
            _refresh();
          },
          decoration: _decoration('Customer Name').copyWith(
            hintText: 'Select or add customer',
            suffixIcon: const Icon(Icons.search_rounded),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final values = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: values.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final customer = values[index];
                  return ListTile(
                    leading: const Icon(Icons.business_outlined),
                    title: Text(
                      customer.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: (customer.address?.trim().isNotEmpty ?? false)
                        ? Text(customer.address!)
                        : null,
                    onTap: () => onSelected(customer),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _itemsCard() {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return _SalesCard(
      title: 'Sales Items',
      icon: Icons.inventory_2_outlined,
      trailing: mobile
          ? null
          : FilledButton.icon(
              onPressed: _saving ? null : _addLine,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Item'),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return Column(
              children: [
                ...List.generate(
                  _lines.length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _SalesItemEditor(
                      key: ValueKey(_lines[index]),
                      line: _lines[index],
                      index: index,
                      itemNameWidth: constraints.maxWidth,
                      items: _items,
                      units: _units,
                      onItemSelected: _selectItem,
                      onRemove: () => _removeLine(index),
                      onChanged: _refresh,
                      mobile: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addLine,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Item'),
                  ),
                ),
              ],
            );
          }
          final tableWidth =
              constraints.maxWidth > 930 ? constraints.maxWidth : 930.0;
          final itemNameWidth = 260 + (tableWidth - 930);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  _SalesItemHeader(itemNameWidth: itemNameWidth),
                  ...List.generate(
                    _lines.length,
                    (index) => _SalesItemEditor(
                      key: ValueKey(_lines[index]),
                      line: _lines[index],
                      index: index,
                      itemNameWidth: itemNameWidth,
                      items: _items,
                      units: _units,
                      onItemSelected: _selectItem,
                      onRemove: () => _removeLine(index),
                      onChanged: _refresh,
                      mobile: false,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _totalCard() {
    if (MediaQuery.sizeOf(context).width < 700) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFBBE8CC)),
        ),
        child: Row(
          children: [
            const Text(
              'Grand Total',
              style: TextStyle(
                color: Color(0xFF166534),
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              'PKR ${_grandTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Color(0xFF16845B),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: MediaQuery.sizeOf(context).width < 500 ? double.infinity : 350,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GRAND TOTAL',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              child: Text(
                'PKR ${_grandTotal.toStringAsFixed(2)}',
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
    final role = AuthService.instance.cachedProfile?.role;
    final canEnterIntoErp = role == 'owner' || role == 'coordinator';
    final actions = <Widget>[
        OutlinedButton.icon(
          onPressed: _saving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
          label: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16845B),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          onPressed: _saving ? null : () => _save(),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text('Complete Cash Sale'),
        ),
        if (canEnterIntoErp)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
            ),
            onPressed:
                _saving ? null : () => _save(enterIntoErp: true),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Enter into ERP'),
          ),
      ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: actions
                .expand((button) => [button, const SizedBox(height: 10)])
                .toList()
              ..removeLast(),
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.end,
          children: actions,
        );
      },
    );
  }
}

class _SaleLineEditor {
  final itemController = TextEditingController();
  final quantityController = TextEditingController();
  final previousRateController = TextEditingController(text: '0.00');
  final salesRateController = TextEditingController();
  final VoidCallback onChanged;
  final Future<void> Function(_SaleLineEditor line, String itemName) onLookup;
  String? unitId;
  Timer? _debounce;
  bool isLookingUp = false;
  bool hasHistory = false;

  _SaleLineEditor({required this.onChanged, required this.onLookup}) {
    itemController.addListener(_scheduleLookup);
    quantityController.addListener(onChanged);
    salesRateController.addListener(onChanged);
  }

  double get quantity => double.tryParse(quantityController.text) ?? 0;
  double get previousRate =>
      double.tryParse(previousRateController.text) ?? 0;
  double get salesRate => double.tryParse(salesRateController.text) ?? 0;
  double get total => quantity * salesRate;

  void _scheduleLookup() {
    _debounce?.cancel();
    final value = itemController.text.trim();
    if (value.isEmpty) return;
    _debounce = Timer(
      const Duration(milliseconds: 650),
      () => onLookup(this, value),
    );
  }

  void cancelLookup() => _debounce?.cancel();

  void dispose() {
    _debounce?.cancel();
    itemController.removeListener(_scheduleLookup);
    quantityController.removeListener(onChanged);
    salesRateController.removeListener(onChanged);
    itemController.dispose();
    quantityController.dispose();
    previousRateController.dispose();
    salesRateController.dispose();
  }
}

class _SalesCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SalesCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.all(mobile ? 14 : 20),
      decoration: BoxDecoration(
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile && trailing != null) ...[
            Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: trailing!),
          ] else
            Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              ?trailing,
            ]),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SalesItemHeader extends StatelessWidget {
  final double itemNameWidth;

  const _SalesItemHeader({required this.itemNameWidth});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          const SizedBox(width: 40, child: _HeaderText('#')),
          SizedBox(
            width: itemNameWidth,
            child: const _HeaderText('Item Name'),
          ),
          const SizedBox(width: 130, child: _HeaderText('Unit')),
          const SizedBox(width: 100, child: _HeaderText('Qty')),
          const SizedBox(width: 140, child: _HeaderText('Previous Rate')),
          const SizedBox(width: 130, child: _HeaderText('Sales Rate')),
          const SizedBox(width: 130, child: _HeaderText('Total')),
        ],
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  final String text;
  const _HeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    );
  }
}

class _SalesItemEditor extends StatelessWidget {
  final _SaleLineEditor line;
  final int index;
  final double itemNameWidth;
  final List<ItemModel> items;
  final List<UnitModel> units;
  final Future<void> Function(_SaleLineEditor line, ItemModel item)
      onItemSelected;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final bool mobile;

  const _SalesItemEditor({
    super.key,
    required this.line,
    required this.index,
    required this.itemNameWidth,
    required this.items,
    required this.units,
    required this.onItemSelected,
    required this.onRemove,
    required this.onChanged,
    required this.mobile,
  });

  Widget _mobileNumberField(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: readOnly,
        fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _mobileItemAutocomplete() {
    return Autocomplete<ItemModel>(
      displayStringForOption: (item) => item.itemName,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return (query.isEmpty
                ? items
                : items.where(
                    (item) => item.itemName.toLowerCase().contains(query),
                  ))
            .take(20);
      },
      onSelected: (item) => unawaited(onItemSelected(line, item)),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) {
            if (line.itemController.text != value) {
              line.itemController.text = value;
            }
          },
          decoration: InputDecoration(
            labelText: 'Item Name',
            hintText: 'Select or add item',
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: line.isLookingUp
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Icon(
                    line.hasHistory
                        ? Icons.history_rounded
                        : Icons.search_rounded,
                    color: line.hasHistory ? const Color(0xFF16845B) : null,
                  ),
          ),
        );
      },
    );
  }

  Widget _mobileEditor() {
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
          Row(
            children: [
              Text(
                'Item ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Remove item',
                onPressed: onRemove,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFCF3E4F),
                ),
              ),
            ],
          ),
          _mobileItemAutocomplete(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(line.unitId),
                  initialValue: line.unitId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: units
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit.id,
                          child: Text(
                            unit.symbol.isEmpty ? unit.unitName : unit.symbol,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    line.unitId = value;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _mobileNumberField(
                  'Quantity',
                  line.quantityController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _mobileNumberField(
                  'Previous Rate',
                  line.previousRateController,
                  readOnly: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _mobileNumberField(
                  'Sales Rate',
                  line.salesRateController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Total: PKR ${line.total.toStringAsFixed(2)}',
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

  Widget _field(
    TextEditingController controller,
    double width, {
    bool readOnly = false,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            isDense: true,
            filled: readOnly,
            fillColor: readOnly ? const Color(0xFFF1F5F9) : null,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mobile) return _mobileEditor();
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('${index + 1}', textAlign: TextAlign.center),
          ),
          SizedBox(
            width: itemNameWidth,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Autocomplete<ItemModel>(
                displayStringForOption: (item) => item.itemName,
                optionsBuilder: (value) {
                  final query = value.text.trim().toLowerCase();
                  return (query.isEmpty
                          ? items
                          : items.where(
                              (item) =>
                                  item.itemName.toLowerCase().contains(query),
                            ))
                      .take(20);
                },
                onSelected: (item) =>
                    unawaited(onItemSelected(line, item)),
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (value) {
                      if (line.itemController.text != value) {
                        line.itemController.text = value;
                      }
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Select or add item',
                      border: const OutlineInputBorder(),
                      suffixIcon: line.isLookingUp
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : Icon(
                              line.hasHistory
                                  ? Icons.history_rounded
                                  : Icons.search_rounded,
                              color: line.hasHistory
                                  ? const Color(0xFF16845B)
                                  : null,
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: DropdownButtonFormField<String>(
                key: ValueKey(line.unitId),
                initialValue: line.unitId,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: units
                    .map(
                      (unit) => DropdownMenuItem(
                        value: unit.id,
                        child: Text(
                          unit.symbol.isEmpty ? unit.unitName : unit.symbol,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  line.unitId = value;
                  onChanged();
                },
              ),
            ),
          ),
          _field(line.quantityController, 100),
          _field(line.previousRateController, 140, readOnly: true),
          _field(line.salesRateController, 130),
          SizedBox(
            width: 100,
            child: Text(
              line.total.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: onRemove,
              icon: const Icon(
                Icons.delete_outline,
                color: Color(0xFFCF3E4F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
