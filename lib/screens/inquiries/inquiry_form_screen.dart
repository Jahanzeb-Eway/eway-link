import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/customer.dart';
import '../../models/item.dart';
import '../../models/unit.dart';
import '../../repositories/customer_repository.dart';
import '../../repositories/inquiry_repository.dart';
import '../../repositories/item_repository.dart';
import '../../repositories/unit_repository.dart';
import '../../repositories/vendor_repository.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_colors.dart';

class InquiryFormScreen extends StatefulWidget {
  final String? inquiryId;

  const InquiryFormScreen({
    super.key,
    this.inquiryId,
  });

  bool get isEditing => inquiryId != null;

  @override
  State<InquiryFormScreen> createState() => _InquiryFormScreenState();
}

class _InquiryFormScreenState extends State<InquiryFormScreen> {
  final _db = SupabaseService.client;
  final _customerController = TextEditingController();
  final _addressController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _inquiryNumberController = TextEditingController();
  final List<_EditableInquiryItem> _lines = [];
  List<_CoordinatorOption> _coordinators = const [];
  List<CustomerModel> _savedCustomers = const [];
  List<ItemModel> _savedItems = const [];
  List<UnitModel> _savedUnits = const [];
  String? _selectedCoordinatorId;

  bool _isLoading = true;
  bool _isSaving = false;
  String _status = 'Pending';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!widget.isEditing) {
      _dueDateController.text = _formatDate(DateTime.now());
      _addLine(notify: false);
    }

    await Future.wait([
      _loadCoordinators(),
      _loadSavedMasterData(),
    ]);
    if (!mounted) return;

    if (widget.isEditing) {
      await _loadInquiry();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _addressController.dispose();
    _dueDateController.dispose();
    _inquiryNumberController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  DateTime _parseDate(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return DateTime.now();
    return DateTime(
      int.tryParse(parts[2]) ?? DateTime.now().year,
      int.tryParse(parts[1]) ?? DateTime.now().month,
      int.tryParse(parts[0]) ?? DateTime.now().day,
    );
  }

  Map<String, dynamic> _relation(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return const {};
  }

  Future<void> _loadCoordinators() async {
    try {
      final response = await _db.rpc('list_inquiry_purchasers');
      final options = List<Map<String, dynamic>>.from(response as List)
          .map(_CoordinatorOption.fromMap)
          .where((option) => option.id.isNotEmpty && option.name.isNotEmpty)
          .toList();

      _coordinators = options;
      if (!widget.isEditing && options.isNotEmpty) {
        final ali = options.where(
          (option) => option.name.trim().toLowerCase() == 'ali',
        );
        _selectedCoordinatorId =
            ali.isNotEmpty ? ali.first.id : options.first.id;
      }
    } catch (_) {
      _coordinators = const [];
    }
  }

  Future<void> _loadSavedMasterData() async {
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
    ]);
    _savedCustomers = List<CustomerModel>.from(results[0] as List);
    _savedItems = List<ItemModel>.from(results[1] as List);
    _savedUnits = List<UnitModel>.from(results[2] as List);
  }

  void _selectCustomer(CustomerModel customer) {
    _customerController.text = customer.customerName;
    _addressController.text = customer.address?.trim() ?? '';
    _refreshTotal();
  }

  Future<void> _selectItem(
    _EditableInquiryItem line,
    ItemModel item,
  ) async {
    line.itemController.text = item.itemName;
    line.cancelLookupDebounce();
    final defaultUnitId = item.defaultUnitId;
    if (defaultUnitId != null && defaultUnitId.isNotEmpty) {
      for (final unit in _savedUnits) {
        if (unit.id == defaultUnitId) {
          line.unitController.text = unit.unitName;
          break;
        }
      }
    }
    await _lookupLastPurchase(line, item.itemName);
  }

  String get _selectedCoordinatorName {
    final selectedId = _selectedCoordinatorId;
    if (selectedId == null) return '';
    for (final option in _coordinators) {
      if (option.id == selectedId) return option.name;
    }
    return '';
  }

  Future<void> _loadInquiry() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        _db.from('inquiries').select('''
          id, inquiry_no, coordinator, coordinator_id, due_date, status,
          grand_total,
          customers(customer_name, address)
        ''').eq('id', widget.inquiryId!).single(),
        _db.from('inquiry_items').select('''
          id, qty, previous_rate, selected_rate, total,
          items(item_name), vendors(vendor_name), units(unit_name)
        ''').eq('inquiry_id', widget.inquiryId!).order('id'),
      ]);
      final header = Map<String, dynamic>.from(results[0] as Map);
      final customer = _relation(header, 'customers');
      final items = List<Map<String, dynamic>>.from(
        (results[1] as List).map((row) => Map<String, dynamic>.from(row as Map)),
      );
      _customerController.text = customer['customer_name']?.toString() ?? '';
      _addressController.text = customer['address']?.toString() ?? '';
      final coordinatorId = header['coordinator_id']?.toString();
      if (coordinatorId != null &&
          _coordinators.any((option) => option.id == coordinatorId)) {
        _selectedCoordinatorId = coordinatorId;
      } else {
        final coordinatorName =
            header['coordinator']?.toString().trim().toLowerCase() ?? '';
        for (final option in _coordinators) {
          if (option.name.trim().toLowerCase() == coordinatorName) {
            _selectedCoordinatorId = option.id;
            break;
          }
        }
      }
      _inquiryNumberController.text = header['inquiry_no']?.toString() ?? '';
      final dueDate = DateTime.tryParse(header['due_date']?.toString() ?? '');
      _dueDateController.text = _formatDate(dueDate?.toLocal() ?? DateTime.now());
      _status = header['status']?.toString() ?? 'Pending';
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..addAll(items.map((row) {
          final item = _relation(row, 'items');
          final vendor = _relation(row, 'vendors');
          final unit = _relation(row, 'units');
          return _EditableInquiryItem(
            itemName: item['item_name']?.toString() ?? '',
            unit: unit['unit_name']?.toString() ?? '',
            quantity: row['qty']?.toString() ?? '',
            vendor: vendor['vendor_name']?.toString() ?? '',
            previousRate: row['previous_rate']?.toString() ?? '',
            rate: row['selected_rate']?.toString() ?? '',
            onChanged: _refreshTotal,
            onItemLookup: _lookupLastPurchase,
          );
        }));
      if (_lines.isEmpty) _addLine(notify: false);
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The inquiry could not be loaded for editing.')),
      );
    }
  }

  void _refreshTotal() {
    if (mounted) setState(() {});
  }

  void _addLine({bool notify = true}) {
    _lines.add(
      _EditableInquiryItem(
        onChanged: _refreshTotal,
        onItemLookup: _lookupLastPurchase,
      ),
    );
    if (notify && mounted) setState(() {});
  }

  Future<void> _lookupLastPurchase(
    _EditableInquiryItem line,
    String itemName,
  ) async {
    if (!_lines.contains(line) || itemName.trim().isEmpty) return;

    line.isLookingUp = true;
    line.hasPurchaseHistory = false;
    _refreshTotal();

    try {
      final result = await InquiryRepository.instance
          .getLastPurchaseForItem(itemName);
      if (!mounted || !_lines.contains(line)) return;
      if (line.itemController.text.trim().toLowerCase() !=
          itemName.trim().toLowerCase()) {
        return;
      }

      if (result != null) {
        line.vendorController.text = result.vendorName;
        line.unitController.text = result.unitName;
        line.previousRateController.text =
            result.rate.toStringAsFixed(2);
        line.hasPurchaseHistory = true;
      }
    } catch (_) {
      if (mounted && _lines.contains(line)) {
        line.hasPurchaseHistory = false;
      }
    } finally {
      if (mounted && _lines.contains(line)) {
        line.isLookingUp = false;
        _refreshTotal();
      }
    }
  }

  void _removeLine(int index) {
    if (_lines.length == 1) {
      _lines.first.clear();
      setState(() {});
      return;
    }
    _lines.removeAt(index).dispose();
    setState(() {});
  }

  double get _grandTotal => _lines.fold(0, (sum, line) => sum + line.total);

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _parseDate(_dueDateController.text),
      firstDate: widget.isEditing ? DateTime(2020) : DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _dueDateController.text = _formatDate(selected));
  }

  Future<void> _saveInquiry({bool complete = false}) async {
    if (_isSaving) return;
    final customerName = _customerController.text.trim();
    final customerInquiryNumber = _inquiryNumberController.text.trim();
    final validLines = _lines.where((line) => line.itemController.text.trim().isNotEmpty).toList();
    if (customerName.isEmpty) {
      _showMessage('Customer Name is required.');
      return;
    }
    if (customerInquiryNumber.isEmpty) {
      _showMessage('Customer Inquiry Number is required.');
      return;
    }
    if (validLines.isEmpty) {
      _showMessage('Please add at least one inquiry item.');
      return;
    }
    if (_selectedCoordinatorId == null ||
        _selectedCoordinatorName.isEmpty) {
      _showMessage('Please select a Purchaser.');
      return;
    }
    for (final line in validLines) {
      if (line.unitController.text.trim().isEmpty || line.quantity <= 0) {
        _showMessage('Every item requires a unit and quantity greater than zero.');
        return;
      }
      if (complete &&
          (line.vendorController.text.trim().isEmpty || line.rate <= 0)) {
        _showMessage(
          'Every item requires a vendor and rate before the inquiry can be completed.',
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final customer = await CustomerRepository.instance.getOrCreate(
        customerName: customerName,
        address: _addressController.text.trim(),
      );
      final desiredStatus = complete ? 'Completed' : _status;
      late final String inquiryId;
      if (widget.isEditing) {
        inquiryId = widget.inquiryId!;
        await InquiryRepository.instance.updateInquiry(
          inquiryId: inquiryId,
          customerId: customer.id,
          coordinatorId: _selectedCoordinatorId!,
          coordinator: _selectedCoordinatorName,
          dueDate: _parseDate(_dueDateController.text),
          status: desiredStatus,
          grandTotal: _grandTotal,
        );
        await InquiryRepository.instance.deleteInquiryItems(inquiryId);
      } else {
        inquiryId = await InquiryRepository.instance.createInquiry(
          inquiryNo: customerInquiryNumber,
          customerId: customer.id,
          coordinatorId: _selectedCoordinatorId!,
          coordinator: _selectedCoordinatorName,
          dueDate: _parseDate(_dueDateController.text),
          status: desiredStatus,
          grandTotal: _grandTotal,
        );
      }

      for (final line in validLines) {
        final unit = await UnitRepository.instance.getByName(line.unitController.text.trim());
        final vendorName = line.vendorController.text.trim();
        final vendor = vendorName.isEmpty
            ? null
            : await VendorRepository.instance.getOrCreate(
                vendorName: vendorName,
              );
        final item = await ItemRepository.instance.getOrCreate(itemName: line.itemController.text.trim(), unitId: unit.id);
        await InquiryRepository.instance.saveInquiryItem(
          inquiryId: inquiryId,
          itemId: item.id,
          unitId: unit.id,
          vendorId: vendor?.id,
          qty: line.quantity,
          previousRate: line.previousRate,
          selectedRate: line.rate,
          total: line.total,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isEditing ? 'Inquiry updated successfully.' : 'Inquiry saved successfully.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final errorText = error.toString();
      if (errorText.contains('inquiries_inquiry_no_key') ||
          errorText.contains('code: 23505')) {
        _showMessage(
          'This Customer Inquiry Number already exists. Enter the customer’s unique inquiry number.',
        );
      } else {
        _showMessage('The inquiry could not be saved. $errorText');
      }
      setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final customerTitle = _customerController.text.trim();
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          mobile
              ? (widget.isEditing ? 'Edit Inquiry' : 'New Inquiry')
              : customerTitle.isEmpty
              ? (widget.isEditing ? 'Edit Customer Inquiry' : 'New Customer Inquiry')
              : customerTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
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
                        _buildHeaderCard(),
                        SizedBox(height: mobile ? 10 : 16),
                        _buildItemsCard(),
                        SizedBox(height: mobile ? 10 : 16),
                        _buildTotalCard(),
                        SizedBox(height: mobile ? 12 : 22),
                        _buildActions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderCard() {
    return _FormCard(
      title: 'Customer Information',
      icon: Icons.business_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 240
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: width,
                child: _buildCustomerAutocomplete(),
              ),
              SizedBox(
                width: width,
                child: _buildField(
                  _FieldData(
                    'Customer Inquiry Number',
                    _inquiryNumberController,
                    widget.isEditing,
                    null,
                    null,
                  ),
                ),
              ),
              SizedBox(width: width, child: _buildCoordinatorField()),
              SizedBox(
                width: width,
                child: _buildField(
                  _FieldData(
                    'Customer Address',
                    _addressController,
                    false,
                    null,
                    null,
                  ),
                ),
              ),
              SizedBox(
                width: width,
                child: _buildField(
                  _FieldData(
                    'Due Date',
                    _dueDateController,
                    true,
                    IconButton(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                    ),
                    null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCoordinatorField() {
    return DropdownButtonFormField<String>(
      key: ValueKey(_selectedCoordinatorId),
      initialValue: _selectedCoordinatorId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Purchaser',
        filled: true,
        fillColor: Colors.white,
        isDense: MediaQuery.sizeOf(context).width < 700,
        contentPadding: MediaQuery.sizeOf(context).width < 700
            ? const EdgeInsets.symmetric(horizontal: 11, vertical: 13)
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      hint: const Text('Select purchaser'),
      items: _coordinators
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.id,
              child: Text(
                option.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _isSaving
          ? null
          : (value) => setState(() => _selectedCoordinatorId = value),
    );
  }

  Widget _buildCustomerAutocomplete() {
    return Autocomplete<CustomerModel>(
      initialValue: TextEditingValue(text: _customerController.text),
      displayStringForOption: (customer) => customer.customerName,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        final matches = query.isEmpty
            ? _savedCustomers
            : _savedCustomers.where(
                (customer) =>
                    customer.customerName.toLowerCase().contains(query),
              );
        return matches.take(20);
      },
      onSelected: _selectCustomer,
      fieldViewBuilder: (
        context,
        textEditingController,
        focusNode,
        onFieldSubmitted,
      ) {
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) {
            _customerController.text = value;
            _refreshTotal();
          },
          onSubmitted: (_) => onFieldSubmitted(),
          decoration: InputDecoration(
            labelText: 'Customer Name',
            hintText: 'Type to select or create a customer',
            suffixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white,
            isDense: MediaQuery.sizeOf(context).width < 700,
            contentPadding: MediaQuery.sizeOf(context).width < 700
                ? const EdgeInsets.symmetric(horizontal: 11, vertical: 13)
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
              constraints: const BoxConstraints(
                maxWidth: 420,
                maxHeight: 320,
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: values.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final customer = values[index];
                  final address = customer.address?.trim() ?? '';
                  return ListTile(
                    leading: const Icon(Icons.business_outlined),
                    title: Text(
                      customer.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: address.isEmpty ? null : Text(address),
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

  Widget _buildField(_FieldData data) {
    return TextField(
      controller: data.controller,
      readOnly: data.readOnly,
      onChanged: (_) => data.onChanged?.call(),
      textCapitalization: TextCapitalization.words,
	      decoration: InputDecoration(
	        labelText: data.label,
	        suffixIcon: data.suffix,
	        filled: true,
	        fillColor: data.readOnly ? const Color(0xFFF1F5F9) : Colors.white,
	        isDense: MediaQuery.sizeOf(context).width < 700,
	        contentPadding: MediaQuery.sizeOf(context).width < 700
	            ? const EdgeInsets.symmetric(horizontal: 11, vertical: 13)
	            : null,
	        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildItemsCard() {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return _FormCard(
      title: 'Inquiry Items',
      icon: Icons.inventory_2_outlined,
      trailing: mobile
          ? null
          : FilledButton.icon(
              onPressed: _addLine,
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
                    child: _ItemEditor(
                      key: ValueKey(_lines[index]),
                      line: _lines[index],
                      index: index,
                      dimensions: _InquiryItemDimensions.forWidth(
                        _InquiryItemDimensions.minimumTableWidth,
                      ),
                      savedItems: _savedItems,
                      savedUnits: _savedUnits,
                      onItemSelected: _selectItem,
                      onRemove: () => _removeLine(index),
                      mobile: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _addLine,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Item'),
                  ),
                ),
              ],
            );
          }
          const minimumWidth = _InquiryItemDimensions.minimumTableWidth;
          final tableWidth = constraints.maxWidth > minimumWidth
              ? constraints.maxWidth
              : minimumWidth;
          final dimensions = _InquiryItemDimensions.forWidth(tableWidth);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ItemHeader(dimensions: dimensions),
                  ...List.generate(_lines.length, (index) => _ItemEditor(
                    key: ValueKey(_lines[index]),
                    line: _lines[index],
                    index: index,
                    dimensions: dimensions,
                    savedItems: _savedItems,
                    savedUnits: _savedUnits,
                    onItemSelected: _selectItem,
                    onRemove: () => _removeLine(index),
                    mobile: false,
                  )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTotalCard() {
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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GRAND TOTAL', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 8),
            FittedBox(child: Text('PKR ${_grandTotal.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.w900))),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return LayoutBuilder(builder: (context, constraints) {
      final buttons = [
        OutlinedButton.icon(onPressed: _isSaving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded), label: const Text('Cancel')),
        FilledButton.icon(onPressed: _isSaving ? null : () => _saveInquiry(), icon: const Icon(Icons.save_outlined), label: Text(widget.isEditing ? 'Update Inquiry' : 'Save Inquiry')),
        FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16845B)), onPressed: _isSaving ? null : () => _saveInquiry(complete: true), icon: const Icon(Icons.check_circle_outline), label: const Text('Save & Complete')),
      ];
      if (constraints.maxWidth < 620) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons.map((button) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SizedBox(height: 50, child: button))).toList());
      }
      return Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons.map((button) => Padding(padding: const EdgeInsets.only(left: 10), child: SizedBox(width: 190, height: 50, child: button))).toList());
    });
  }
}

class _EditableInquiryItem {
  final itemController = TextEditingController();
  final unitController = TextEditingController();
  final qtyController = TextEditingController();
  final vendorController = TextEditingController();
  final previousRateController = TextEditingController();
  final rateController = TextEditingController();
  final VoidCallback onChanged;
  final Future<void> Function(_EditableInquiryItem line, String itemName)
      onItemLookup;
  Timer? _lookupDebounce;
  bool isLookingUp = false;
  bool hasPurchaseHistory = false;

  _EditableInquiryItem({String itemName = '', String unit = '', String quantity = '', String vendor = '', String previousRate = '', String rate = '', required this.onChanged, required this.onItemLookup}) {
    itemController.text = itemName;
    unitController.text = unit;
    qtyController.text = quantity;
    vendorController.text = vendor;
    previousRateController.text = previousRate;
    rateController.text = rate;
    qtyController.addListener(onChanged);
    rateController.addListener(onChanged);
    itemController.addListener(_scheduleLookup);
  }
  void _scheduleLookup() {
    _lookupDebounce?.cancel();
    hasPurchaseHistory = false;
    final itemName = itemController.text.trim();
    if (itemName.isEmpty) {
      isLookingUp = false;
      onChanged();
      return;
    }
    _lookupDebounce = Timer(
      const Duration(milliseconds: 650),
      () => onItemLookup(this, itemName),
    );
  }
  void cancelLookupDebounce() => _lookupDebounce?.cancel();
  double get quantity => double.tryParse(qtyController.text) ?? 0;
  double get previousRate => double.tryParse(previousRateController.text) ?? 0;
  double get rate => double.tryParse(rateController.text) ?? 0;
  double get total => quantity * rate;
  void clear() { itemController.clear(); unitController.clear(); qtyController.clear(); vendorController.clear(); previousRateController.clear(); rateController.clear(); }
  void dispose() { _lookupDebounce?.cancel(); itemController.removeListener(_scheduleLookup); qtyController.removeListener(onChanged); rateController.removeListener(onChanged); itemController.dispose(); unitController.dispose(); qtyController.dispose(); vendorController.dispose(); previousRateController.dispose(); rateController.dispose(); }
}

class _FieldData {
  final String label;
  final TextEditingController controller;
  final bool readOnly;
  final Widget? suffix;
  final VoidCallback? onChanged;
  const _FieldData(this.label, this.controller, this.readOnly, this.suffix, this.onChanged);
}

class _CoordinatorOption {
  final String id;
  final String name;

  const _CoordinatorOption({
    required this.id,
    required this.name,
  });

  factory _CoordinatorOption.fromMap(Map<String, dynamic> map) {
    return _CoordinatorOption(
      id: map['id']?.toString() ?? '',
      name: map['full_name']?.toString().trim() ?? '',
    );
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _FormCard({required this.title, required this.icon, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
    padding: EdgeInsets.all(mobile ? 14 : 20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x0D0F172A), blurRadius: 18, offset: Offset(0, 6))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (mobile && trailing != null) ...[
        Row(children: [Icon(icon, color: AppColors.primary), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))]),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerRight, child: trailing!),
      ] else
        Row(children: [Icon(icon, color: AppColors.primary), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), ?trailing]),
      const SizedBox(height: 18), child,
    ]),
  );
  }
}

class _InquiryItemDimensions {
  static const double number = 40;
  static const double item = 230;
  static const double unit = 110;
  static const double quantity = 100;
  static const double vendor = 190;
  static const double previousRate = 140;
  static const double rate = 130;
  static const double minimumTotal = 140;
  static const double action = 54;
  static const double minimumTableWidth = number +
      item +
      unit +
      quantity +
      vendor +
      previousRate +
      rate +
      minimumTotal +
      action;

  final double total;

  const _InquiryItemDimensions._({required this.total});

  factory _InquiryItemDimensions.forWidth(double tableWidth) {
    final additionalWidth = tableWidth - minimumTableWidth;
    return _InquiryItemDimensions._(
      total: minimumTotal + (additionalWidth > 0 ? additionalWidth : 0),
    );
  }
}

class _ItemHeader extends StatelessWidget {
  final _InquiryItemDimensions dimensions;

  const _ItemHeader({required this.dimensions});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    color: const Color(0xFF1E293B),
    child: Row(children: [
      const SizedBox(width: _InquiryItemDimensions.number, child: Text('#', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      const _HeaderCell('Item Name', _InquiryItemDimensions.item),
      const _HeaderCell('Unit', _InquiryItemDimensions.unit),
      const _HeaderCell('Qty', _InquiryItemDimensions.quantity),
      const _HeaderCell('Vendor', _InquiryItemDimensions.vendor),
      const _HeaderCell('Previous Rate', _InquiryItemDimensions.previousRate),
      const _HeaderCell('Rate', _InquiryItemDimensions.rate),
      _HeaderCell('Total', dimensions.total),
      const SizedBox(width: _InquiryItemDimensions.action),
    ]),
  );
}

class _HeaderCell extends StatelessWidget {
  final String text; final double width; const _HeaderCell(this.text, this.width);
  @override Widget build(BuildContext context) => SizedBox(width: width, child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)));
}

class _ItemEditor extends StatelessWidget {
  final _EditableInquiryItem line;
  final int index;
  final _InquiryItemDimensions dimensions;
  final List<ItemModel> savedItems;
  final List<UnitModel> savedUnits;
  final Future<void> Function(_EditableInquiryItem line, ItemModel item)
      onItemSelected;
  final VoidCallback onRemove;
  final bool mobile;

  const _ItemEditor({
    super.key,
    required this.line,
    required this.index,
    required this.dimensions,
    required this.savedItems,
    required this.savedUnits,
    required this.onItemSelected,
    required this.onRemove,
    required this.mobile,
  });

  Widget field(TextEditingController controller, double width, {bool numeric = false, Widget? suffixIcon}) => SizedBox(width: width, child: Padding(padding: const EdgeInsets.all(5), child: TextField(controller: controller, keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), suffixIcon: suffixIcon))));

  String _unitName(ItemModel item) {
    final unitId = item.defaultUnitId;
    if (unitId == null) return '';
    for (final unit in savedUnits) {
      if (unit.id == unitId) return unit.unitName;
    }
    return '';
  }

  Widget _itemAutocomplete({double? width, bool showLabel = false}) {
    return SizedBox(
      width: width ?? _InquiryItemDimensions.item,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Autocomplete<ItemModel>(
          initialValue: TextEditingValue(text: line.itemController.text),
          displayStringForOption: (item) => item.itemName,
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            final matches = query.isEmpty
                ? savedItems
                : savedItems.where(
                    (item) => item.itemName.toLowerCase().contains(query),
                  );
            return matches.take(20);
          },
          onSelected: (item) => unawaited(onItemSelected(line, item)),
          fieldViewBuilder: (
            context,
            textEditingController,
            focusNode,
            onFieldSubmitted,
          ) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.words,
              onChanged: (value) {
                if (line.itemController.text != value) {
                  line.itemController.text = value;
                }
              },
              onSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                isDense: true,
                labelText: showLabel ? 'Item Name' : null,
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
                    : line.hasPurchaseHistory
                        ? const Tooltip(
                            message: 'Last vendor and purchase rate loaded',
                            child: Icon(
                              Icons.history_rounded,
                              color: Color(0xFF16845B),
                            ),
                          )
                        : const Icon(Icons.search_rounded, size: 20),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final values = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 360,
                    maxHeight: 300,
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: values.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, optionIndex) {
                      final item = values[optionIndex];
                      final unitName = _unitName(item);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(
                          item.itemName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: unitName.isEmpty
                            ? null
                            : Text('Default unit: $unitName'),
                        onTap: () => onSelected(item),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _mobileField(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: readOnly,
        fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
        border: const OutlineInputBorder(),
      ),
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
          _itemAutocomplete(width: double.infinity, showLabel: true),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _mobileField('Unit', line.unitController)),
              const SizedBox(width: 10),
              Expanded(
                child: _mobileField(
                  'Quantity',
                  line.qtyController,
                  numeric: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _mobileField(
                  'Vendor',
                  line.vendorController,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _mobileField(
                  'Rate',
                  line.rateController,
                  numeric: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _mobileField(
                  'Previous Rate',
                  line.previousRateController,
                  numeric: true,
                  readOnly: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 49),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBE8CC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'PKR ${line.total.toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF16845B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override Widget build(BuildContext context) => mobile
      ? _mobileEditor()
      : Container(
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
    child: Row(children: [
      SizedBox(width: _InquiryItemDimensions.number, child: Text('${index + 1}', textAlign: TextAlign.center)),
      _itemAutocomplete(),
      field(line.unitController, _InquiryItemDimensions.unit),
      field(line.qtyController, _InquiryItemDimensions.quantity, numeric: true),
      field(line.vendorController, _InquiryItemDimensions.vendor),
      field(line.previousRateController, _InquiryItemDimensions.previousRate, numeric: true),
      field(line.rateController, _InquiryItemDimensions.rate, numeric: true),
      SizedBox(
        width: dimensions.total,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'PKR ${line.total.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      SizedBox(width: _InquiryItemDimensions.action, child: IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline, color: Color(0xFFCF3E4F)))),
    ]),
  );
}
