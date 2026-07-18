import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/cash_sale.dart';
import '../../repositories/cash_sales_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';

class CashSaleDetailsScreen extends StatefulWidget {
  final String cashSaleId;

  const CashSaleDetailsScreen({
    super.key,
    required this.cashSaleId,
  });

  @override
  State<CashSaleDetailsScreen> createState() =>
      _CashSaleDetailsScreenState();
}

class _CashSaleDetailsScreenState extends State<CashSaleDetailsScreen> {
  CashSale? _sale;
  bool _loading = true;
  bool _updating = false;
  bool _exporting = false;
  String? _error;

  bool get _canManageErp {
    final role = AuthService.instance.cachedProfile?.role;
    return role == 'owner' || role == 'coordinator';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await CashSalesRepository.instance.getSale(widget.cashSaleId);
      if (!mounted) return;
      setState(() {
        _sale = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The cash sale could not be loaded. Please try again.';
        _loading = false;
      });
    }
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

  String _quantity(double quantity) {
    return quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(3);
  }

  String _dateTime(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _markEnteredIntoErp() async {
    final sale = _sale;
    if (sale == null || sale.isEnteredIntoErp || _updating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.account_balance_outlined,
          color: AppColors.primary,
          size: 36,
        ),
        title: const Text('Confirm ERP entry'),
        content: Text(
          'Confirm that ${sale.saleNumber} has been entered into the ERP. '
          'This action will close the ticket.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Entered into ERP'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _updating = true);
    try {
      await CashSalesRepository.instance.markEnteredIntoErp(sale.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash sale marked as entered into ERP.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _updating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only an owner or coordinator can confirm the ERP entry.',
          ),
        ),
      );
    }
  }

  Future<Uint8List> _buildPdf() async {
    final sale = _sale!;
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            sale.customerName,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Cash Sale ${sale.saleNumber}'),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _pdfInfo('Customer Name', sale.customerName),
              _pdfInfo('Sales Ticket Number', sale.saleNumber),
              _pdfInfo(
                'Customer Address',
                sale.customerAddress.isEmpty ? '—' : sale.customerAddress,
              ),
              _pdfInfo('Sales Person', sale.salesPersonName),
              _pdfInfo('Created', _dateTime(sale.createdAt)),
              _pdfInfo('Status', sale.status),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text(
            'Sales Items',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headers: const [
              'Item',
              'Unit',
              'Qty',
              'Previous Rate',
              'Sales Rate',
              'Total',
            ],
            data: sale.items
                .map(
                  (item) => [
                    item.itemName,
                    item.unitName,
                    _quantity(item.quantity),
                    _money(item.previousRate),
                    _money(item.salesRate),
                    _money(item.total),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Grand Total: PKR ${_money(sale.grandTotal)}',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  pw.TableRow _pdfInfo(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(7),
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(7),
          child: pw.Text(value),
        ),
      ],
    );
  }

  String get _exportName =>
      'EWAY_Cash_Sale_${_sale!.saleNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  Future<void> _runExport(Future<void> Function() action) async {
    if (_exporting || _sale == null) return;
    setState(() => _exporting = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The export could not be completed.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _sharePdf() async {
    await _runExport(() async {
      final bytes = await _buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: '$_exportName.pdf');
    });
  }

  Future<void> _printPdf() async {
    await _runExport(() async {
      final bytes = await _buildPdf();
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: _exportName);
    });
  }

  Future<void> _shareJpeg() async {
    await _runExport(() async {
      final pdfBytes = await _buildPdf();
      final files = <XFile>[];
      var pageNumber = 0;
      await for (final page in Printing.raster(pdfBytes, dpi: 144)) {
        pageNumber++;
        final png = await page.toPng();
        final decoded = image_lib.decodePng(png);
        if (decoded == null) throw StateError('JPEG generation failed.');
        files.add(
          XFile.fromData(
            Uint8List.fromList(image_lib.encodeJpg(decoded, quality: 92)),
            mimeType: 'image/jpeg',
            name: pageNumber == 1
                ? '$_exportName.jpg'
                : '${_exportName}_page_$pageNumber.jpg',
          ),
        );
      }
      if (files.isEmpty) throw StateError('JPEG generation failed.');
      await SharePlus.instance.share(
        ShareParams(files: files, subject: _exportName),
      );
    });
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
          mobile ? 'Cash Invoice' : _sale?.customerName ?? 'Cash Sale Details',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_sale != null)
            PopupMenuButton<String>(
              tooltip: 'Export and print',
              onSelected: (value) {
                if (value == 'pdf') _sharePdf();
                if (value == 'jpeg') _shareJpeg();
                if (value == 'print') _printPdf();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('Download PDF'),
                  ),
                ),
                PopupMenuItem(
                  value: 'jpeg',
                  child: ListTile(
                    leading: Icon(Icons.image_outlined),
                    title: Text('Download JPEG'),
                  ),
                ),
                PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text('Print'),
                  ),
                ),
              ],
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded),
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _sale == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 54, color: Color(0xFFCF3E4F)),
              const SizedBox(height: 12),
              Text(_error ?? 'Cash sale not found.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final sale = _sale!;
    final statusColor = sale.isEnteredIntoErp
        ? const Color(0xFF2563EB)
        : const Color(0xFF16845B);
    if (MediaQuery.sizeOf(context).width < 700) {
      return _mobileBody(sale, statusColor);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sale.customerName,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sale.saleNumber,
                              style: const TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            sale.status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Wrap(
                      spacing: 28,
                      runSpacing: 18,
                      children: [
                        _Fact('Customer Address', sale.customerAddress),
                        _Fact('Sales Person', sale.salesPersonName),
                        _Fact('Created', _dateTime(sale.createdAt)),
                        _Fact('Grand Total', 'PKR ${_money(sale.grandTotal)}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _itemsTable(sale),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _sharePdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _shareJpeg,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('JPEG'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _printPdf,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print'),
                  ),
                  if (_canManageErp && !sale.isEnteredIntoErp)
                    FilledButton.icon(
                      onPressed: _updating ? null : _markEnteredIntoErp,
                      icon: const Icon(Icons.account_balance_outlined),
                      label: const Text('Entered into ERP'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileBody(CashSale sale, Color statusColor) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: _mobileCardDecoration(),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sale.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F2942),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          sale.status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: _mobileFact(
                          Icons.person_outline_rounded,
                          'Customer Name',
                          sale.customerName,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _mobileFact(
                          Icons.receipt_long_outlined,
                          'Invoice Number',
                          sale.saleNumber,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _mobileFact(
                          Icons.badge_outlined,
                          'Sales Person',
                          sale.salesPersonName,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _mobileFact(
                          Icons.schedule_outlined,
                          'Created',
                          _dateTime(sale.createdAt),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 15),
                  _mobileFact(
                    Icons.location_on_outlined,
                    'Customer Address',
                    sale.customerAddress,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Items (${sale.items.length})',
                  style: const TextStyle(
                    color: Color(0xFF0F2942),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                _mobileExport(Icons.picture_as_pdf_outlined, 'PDF', const Color(0xFFDC2626), _sharePdf),
                _mobileExport(Icons.image_outlined, 'JPEG', const Color(0xFF16845B), _shareJpeg),
                _mobileExport(Icons.print_outlined, 'Print', const Color(0xFF2563EB), _printPdf),
              ],
            ),
            const SizedBox(height: 8),
            _itemsTable(sale),
            const SizedBox(height: 10),
            Container(
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
                    'PKR ${_money(sale.grandTotal)}',
                    style: const TextStyle(
                      color: Color(0xFF16845B),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (_canManageErp && !sale.isEnteredIntoErp) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _updating ? null : _markEnteredIntoErp,
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Enter in ERP'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mobileFact(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF5FB),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: AppColors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
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
          ),
        ),
      ],
    );
  }

  Widget _mobileExport(
    IconData icon,
    String label,
    Color color,
    VoidCallback action,
  ) {
    return InkWell(
      onTap: _exporting ? null : action,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _mobileCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFD9E3EC)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0F172A),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  Widget _itemsTable(CashSale sale) {
    if (MediaQuery.sizeOf(context).width < 700) {
      return Column(
        children: sale.items.asMap().entries.map((entry) {
          final item = entry.value;
          return Padding(
            padding: EdgeInsets.only(
              bottom: entry.key == sale.items.length - 1 ? 0 : 12,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 10) / 2;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _cashItemFact(width, 'Unit', item.unitName),
                          _cashItemFact(
                            width,
                            'Quantity',
                            _quantity(item.quantity),
                          ),
                          _cashItemFact(
                            width,
                            'Previous Rate',
                            'PKR ${_money(item.previousRate)}',
                          ),
                          _cashItemFact(
                            width,
                            'Sales Rate',
                            'PKR ${_money(item.salesRate)}',
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: PKR ${_money(item.total)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          columns: const [
            DataColumn(label: Text('Item Name')),
            DataColumn(label: Text('Unit')),
            DataColumn(label: Text('Quantity'), numeric: true),
            DataColumn(label: Text('Previous Rate'), numeric: true),
            DataColumn(label: Text('Sales Rate'), numeric: true),
            DataColumn(label: Text('Total'), numeric: true),
          ],
          rows: sale.items
              .map(
                (item) => DataRow(
                  cells: [
                    DataCell(Text(item.itemName)),
                    DataCell(Text(item.unitName)),
                    DataCell(Text(_quantity(item.quantity))),
                    DataCell(Text('PKR ${_money(item.previousRate)}')),
                    DataCell(Text('PKR ${_money(item.salesRate)}')),
                    DataCell(
                      Text(
                        'PKR ${_money(item.total)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cashItemFact(double width, String label, String value) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;

  const _Fact(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final display = value.trim().isEmpty ? '—' : value;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: screenWidth < 600 ? (screenWidth - 76) / 2 : 230,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 5),
          Text(display, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
