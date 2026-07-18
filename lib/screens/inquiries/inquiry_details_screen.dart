import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../repositories/inquiry_repository.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_colors.dart';
import 'inquiry_form_screen.dart';
import 'inquiry_pricing_screen.dart';

class InquiryDetailsScreen extends StatefulWidget {
  final String inquiryId;

  const InquiryDetailsScreen({
    super.key,
    required this.inquiryId,
  });

  @override
  State<InquiryDetailsScreen> createState() =>
      _InquiryDetailsScreenState();
}

class _InquiryDetailsScreenState extends State<InquiryDetailsScreen> {
  final _db = SupabaseService.client;

  Map<String, dynamic>? _inquiry;
  List<Map<String, dynamic>> _items = const [];
  bool _isLoading = true;
  bool _isCompleting = false;
  bool _isRejecting = false;
  bool _isExporting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInquiry();
  }

  Future<void> _loadInquiry() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _db
            .from('inquiries')
            .select('''
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
                customer_name,
                address
              )
            ''')
            .eq('id', widget.inquiryId)
            .single(),
        _db
            .from('inquiry_items')
            .select('''
              id,
              qty,
              previous_rate,
              selected_rate,
              total,
              items(item_name),
              vendors(vendor_name),
              units(unit_name)
            ''')
            .eq('inquiry_id', widget.inquiryId)
            .order('id'),
      ]);

      if (!mounted) return;
      setState(() {
        _inquiry = Map<String, dynamic>.from(results[0] as Map);
        _items = List<Map<String, dynamic>>.from(
          (results[1] as List).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
        _isLoading = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('0 rows') || message.contains('PGRST116')) {
      return 'This inquiry could not be found. It may have been removed.';
    }
    return 'The inquiry could not be loaded. Please check your connection and try again.';
  }

  bool get _canEditInquiry {
    final profile = AuthService.instance.cachedProfile;
    final inquiry = _inquiry;
    if (profile == null || inquiry == null) return false;
    if (profile.isOwner) return true;
    if (profile.role == 'coordinator') {
      return inquiry['created_by']?.toString() == profile.id;
    }
    if (profile.role == 'employee') {
      return true;
    }
    return false;
  }

  bool get _canCompleteOrReject {
    final profile = AuthService.instance.cachedProfile;
    final inquiry = _inquiry;
    if (profile == null || inquiry == null) return false;
    return profile.isOwner || profile.role == 'employee';
  }

  bool get _canRejectInquiry {
    final profile = AuthService.instance.cachedProfile;
    final inquiry = _inquiry;
    if (profile == null || inquiry == null) return false;
    return profile.isOwner ||
        (profile.role == 'coordinator' &&
            inquiry['created_by']?.toString() == profile.id);
  }

  String _text(dynamic value, {String fallback = '—'}) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) {
    final amount = _number(value);
    final parts = amount.toStringAsFixed(2).split('.');
    final digits = parts.first;
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      final remaining = digits.length - index;
      buffer.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return '${buffer.toString()}.${parts.last}';
  }

  String _quantity(dynamic value) {
    final quantity = _number(value);
    return quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2);
  }

  String _date(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(parsed.day)}/${twoDigits(parsed.month)}/${parsed.year}';
  }

  Map<String, dynamic> _relation(
    Map<String, dynamic> source,
    String key,
  ) {
    final value = source[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return const {};
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

  Future<void> _completeInquiry() async {
    if (_isCompleting || _inquiry == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete inquiry?'),
        content: const Text(
          'This will mark the inquiry as completed. You can still view all of its details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isCompleting = true);

    try {
      await InquiryRepository.instance.completeInquiry(widget.inquiryId);
      if (!mounted) return;
      setState(() {
        _inquiry = {...?_inquiry, 'status': 'Completed'};
        _isCompleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inquiry marked as completed.')),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to complete the inquiry. Please try again.'),
        ),
      );
    }
  }

  Future<void> _rejectInquiry() async {
    if (_isRejecting || _inquiry == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.block_rounded,
          color: Color(0xFF9F1239),
          size: 36,
        ),
        title: const Text('Reject inquiry?'),
        content: const Text(
          'Use rejection when this inquiry cannot be processed. It will be moved to the Rejected category and locked from further editing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF9F1239),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.block_rounded),
            label: const Text('Reject Inquiry'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isRejecting = true);

    try {
      await InquiryRepository.instance.rejectInquiry(widget.inquiryId);
      if (!mounted) return;
      setState(() {
        _inquiry = {...?_inquiry, 'status': 'Rejected'};
        _isRejecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inquiry moved to Rejected.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRejecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to reject the inquiry. Please try again.'),
        ),
      );
    }
  }

  Future<Uint8List> _buildPdf() async {
    final inquiry = _inquiry!;
    final customer = _relation(inquiry, 'customers');
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          pw.Text(
            _text(customer['customer_name'], fallback: 'Customer Inquiry'),
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Inquiry ${_text(inquiry['inquiry_no'])}'),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _pdfInfoRow('Customer Name', _text(customer['customer_name'])),
              _pdfInfoRow('Inquiry Number', _text(inquiry['inquiry_no'])),
              _pdfInfoRow('Customer Address', _text(customer['address'])),
              _pdfInfoRow('Purchaser', _text(inquiry['coordinator'])),
              _pdfInfoRow('Due Date', _date(inquiry['due_date'])),
              _pdfInfoRow('Status', _text(inquiry['status'])),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text('Inquiry Items', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headers: const ['Item', 'Unit', 'Qty', 'Vendor', 'Previous', 'Rate', 'Total'],
            data: _items.map((item) {
              final itemRecord = _relation(item, 'items');
              final unit = _relation(item, 'units');
              final vendor = _relation(item, 'vendors');
              return [
                _text(itemRecord['item_name']),
                _text(unit['unit_name']),
                _quantity(item['qty']),
                _text(vendor['vendor_name']),
                _money(item['previous_rate']),
                _money(item['selected_rate']),
                _money(item['total']),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Grand Total: PKR ${_money(inquiry['grand_total'])}',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  pw.TableRow _pdfInfoRow(String label, String value) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(7),
        child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ),
      pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(value)),
    ]);
  }

  String get _exportName {
    final inquiryNo = _text(_inquiry?['inquiry_no'], fallback: widget.inquiryId);
    return 'EWAY_Inquiry_${inquiryNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
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
        final pngBytes = await page.toPng();
        final decoded = image_lib.decodePng(pngBytes);
        if (decoded == null) {
          throw StateError('Could not encode inquiry page $pageNumber.');
        }
        final jpegBytes = Uint8List.fromList(
          image_lib.encodeJpg(decoded, quality: 92),
        );
        files.add(
          XFile.fromData(
            jpegBytes,
            mimeType: 'image/jpeg',
            name: pageNumber == 1
                ? '$_exportName.jpg'
                : '${_exportName}_page_$pageNumber.jpg',
          ),
        );
      }

      if (files.isEmpty) {
        throw StateError('The inquiry image could not be generated.');
      }

      await SharePlus.instance.share(
        ShareParams(
          files: files,
          subject: _exportName,
        ),
      );
    });
  }

  Future<void> _runExport(Future<void> Function() action) async {
    if (_isExporting || _inquiry == null) return;
    setState(() => _isExporting = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The export could not be completed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _editInquiry() async {
    final isEmployee =
        AuthService.instance.cachedProfile?.role == 'employee';
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => isEmployee
            ? InquiryPricingScreen(inquiryId: widget.inquiryId)
            : InquiryFormScreen(inquiryId: widget.inquiryId),
      ),
    );
    if (changed == true && mounted) await _loadInquiry();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          mobile
              ? 'Inquiry View'
              : _inquiry == null
              ? 'Inquiry Details'
              : _text(_relation(_inquiry!, 'customers')['customer_name'], fallback: 'Inquiry Details'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_inquiry != null)
            PopupMenuButton<String>(
              tooltip: 'Export and print',
              onSelected: (value) {
                if (value == 'pdf') _sharePdf();
                if (value == 'jpeg') _shareJpeg();
                if (value == 'print') _printPdf();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Download PDF'))),
                PopupMenuItem(value: 'jpeg', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Download JPEG'))),
                PopupMenuItem(value: 'print', child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Print'))),
              ],
              icon: _isExporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.ios_share_rounded),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadInquiry,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null || _inquiry == null) {
      return _ErrorView(
        message: _errorMessage ?? 'The inquiry could not be loaded.',
        onRetry: _loadInquiry,
      );
    }

    final inquiry = _inquiry!;
    final customer = _relation(inquiry, 'customers');
    final status = _text(inquiry['status'], fallback: 'Pending');
    final statusColor = _statusColor(status);
    final completed = status.toLowerCase() == 'completed';
    final rejected = status.toLowerCase() == 'rejected';

    if (MediaQuery.sizeOf(context).width < 700) {
      return _buildMobileBody(
        inquiry: inquiry,
        customer: customer,
        status: status,
        statusColor: statusColor,
        completed: completed,
        rejected: rejected,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 1000 ? 32.0 : 16.0;
        return RefreshIndicator(
          onRefresh: _loadInquiry,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPageHeader(inquiry, customer, status, statusColor),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Customer Information',
                      icon: Icons.business_outlined,
                      child: _buildInformationGrid(inquiry, customer),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Inquiry Items',
                      icon: Icons.inventory_2_outlined,
                      trailing: Text(
                        '${_items.length} ${_items.length == 1 ? 'item' : 'items'}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: _items.isEmpty
                          ? const _EmptyItems()
                          : _buildItemsTable(),
                    ),
                    const SizedBox(height: 16),
                    _buildSummary(inquiry),
                    const SizedBox(height: 20),
                    _buildActions(completed, rejected),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileBody({
    required Map<String, dynamic> inquiry,
    required Map<String, dynamic> customer,
    required String status,
    required Color statusColor,
    required bool completed,
    required bool rejected,
  }) {
    final customerName = _text(
      customer['customer_name'],
      fallback: 'Unnamed Customer',
    );
    return RefreshIndicator(
      onRefresh: _loadInquiry,
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          customerName,
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
                      _StatusBadge(label: status, color: statusColor),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: _mobileOverviewFact(
                          Icons.person_outline_rounded,
                          'Customer Name',
                          customerName,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _mobileOverviewFact(
                          Icons.tag_rounded,
                          'Inquiry Number',
                          _text(inquiry['inquiry_no']),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _mobileOverviewFact(
                          Icons.badge_outlined,
                          'Purchaser',
                          _text(inquiry['coordinator']),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _mobileOverviewFact(
                          Icons.event_outlined,
                          'Due Date',
                          _date(inquiry['due_date']),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 15),
                  _mobileOverviewFact(
                    Icons.location_on_outlined,
                    'Customer Address',
                    _text(customer['address']),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Items (${_items.length})',
                  style: const TextStyle(
                    color: Color(0xFF0F2942),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                _mobileExportButton(
                  Icons.picture_as_pdf_outlined,
                  'PDF',
                  const Color(0xFFDC2626),
                  _sharePdf,
                ),
                _mobileExportButton(
                  Icons.image_outlined,
                  'JPEG',
                  const Color(0xFF16845B),
                  _shareJpeg,
                ),
                _mobileExportButton(
                  Icons.print_outlined,
                  'Print',
                  const Color(0xFF2563EB),
                  _printPdf,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty) const _EmptyItems() else _buildItemsTable(),
            const SizedBox(height: 10),
            _buildMobileGrandTotal(inquiry),
            const SizedBox(height: 12),
            _buildActions(completed, rejected),
          ],
        ),
      ),
    );
  }

  Widget _mobileOverviewFact(IconData icon, String label, String value) {
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

  Widget _mobileExportButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback action,
  ) {
    return InkWell(
      onTap: _isExporting ? null : action,
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

  Widget _buildMobileGrandTotal(Map<String, dynamic> inquiry) {
    final calculated = _items.fold<double>(
      0,
      (sum, item) => sum + _number(item['total']),
    );
    final saved = _number(inquiry['grand_total']);
    final value = saved == 0 && calculated != 0 ? calculated : saved;
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
            'PKR ${_money(value)}',
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

  Widget _buildPageHeader(
    Map<String, dynamic> inquiry,
    Map<String, dynamic> customer,
    String status,
    Color statusColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: .82)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 14,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(customer['customer_name'], fallback: 'Unnamed Customer'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Inquiry ${_text(inquiry['inquiry_no'])}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .82),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationGrid(
    Map<String, dynamic> inquiry,
    Map<String, dynamic> customer,
  ) {
    final fields = <_InfoData>[
      _InfoData('Customer Name', _text(customer['customer_name']), Icons.person_outline),
      _InfoData('Inquiry Number', _text(inquiry['inquiry_no']), Icons.tag_rounded),
      _InfoData('Purchaser', _text(inquiry['coordinator']), Icons.badge_outlined),
      _InfoData('Due Date', _date(inquiry['due_date']), Icons.event_outlined),
      _InfoData('Customer Address', _text(customer['address']), Icons.location_on_outlined),
      _InfoData('Created On', _date(inquiry['created_at']), Icons.schedule_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 300
                ? 2
                : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: fields
              .map((field) => SizedBox(width: width, child: _InfoField(data: field)))
              .toList(),
        );
      },
    );
  }

  Widget _buildItemsTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            children: _items.asMap().entries.map((entry) {
              final item = entry.value;
              final itemRecord = _relation(item, 'items');
              final unit = _relation(item, 'units');
              final vendor = _relation(item, 'vendors');
              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == _items.length - 1 ? 0 : 12,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDCE4EC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(itemRecord['item_name']),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final factWidth = (constraints.maxWidth - 10) / 2;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: factWidth,
                                child: _mobileItemFact(
                                  'Unit',
                                  _text(unit['unit_name']),
                                ),
                              ),
                              SizedBox(
                                width: factWidth,
                                child: _mobileItemFact(
                                  'Quantity',
                                  _quantity(item['qty']),
                                ),
                              ),
                              SizedBox(
                                width: factWidth,
                                child: _mobileItemFact(
                                  'Vendor',
                                  _text(vendor['vendor_name']),
                                ),
                              ),
                              SizedBox(
                                width: factWidth,
                                child: _mobileItemFact(
                                  'Previous Rate',
                                  'PKR ${_money(item['previous_rate'])}',
                                ),
                              ),
                              SizedBox(
                                width: factWidth,
                                child: _mobileItemFact(
                                  'Selected Rate',
                                  'PKR ${_money(item['selected_rate'])}',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 22),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Total: PKR ${_money(item['total'])}',
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
        final tableWidth = constraints.maxWidth < 1050
            ? 1050.0
            : constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
            headingTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            dataRowMinHeight: 58,
            dataRowMaxHeight: 68,
            dividerThickness: 1,
            columns: const [
              DataColumn(label: SizedBox(width: 190, child: Text('Item Name'))),
              DataColumn(label: Text('Unit')),
              DataColumn(label: Text('Quantity'), numeric: true),
              DataColumn(label: SizedBox(width: 150, child: Text('Vendor'))),
              DataColumn(label: Text('Previous Rate'), numeric: true),
              DataColumn(label: Text('Selected Rate'), numeric: true),
              DataColumn(label: Text('Total'), numeric: true),
            ],
                  rows: _items.map((item) {
              final itemRecord = _relation(item, 'items');
              final unit = _relation(item, 'units');
              final vendor = _relation(item, 'vendors');
              return DataRow(
                cells: [
                  DataCell(Text(
                    _text(itemRecord['item_name']),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  )),
                  DataCell(Text(_text(unit['unit_name']))),
                  DataCell(Text(_quantity(item['qty']))),
                  DataCell(Text(_text(vendor['vendor_name']))),
                  DataCell(Text('PKR ${_money(item['previous_rate'])}')),
                  DataCell(Text('PKR ${_money(item['selected_rate'])}')),
                  DataCell(Text(
                    'PKR ${_money(item['total'])}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
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

  Widget _mobileItemFact(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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

  Widget _buildSummary(Map<String, dynamic> inquiry) {
    final calculatedTotal = _items.fold<double>(
      0,
      (sum, item) => sum + _number(item['total']),
    );
    final savedTotal = _number(inquiry['grand_total']);
    final grandTotal = savedTotal == 0 && calculatedTotal != 0
        ? calculatedTotal
        : savedTotal;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: MediaQuery.sizeOf(context).width < 500 ? double.infinity : 350,
        padding: const EdgeInsets.all(20),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GRAND TOTAL',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'PKR ${_money(grandTotal)}',
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

  Widget _buildActions(bool completed, bool rejected) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final backButton = OutlinedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back'),
        );
        final completeButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16845B),
            foregroundColor: Colors.white,
          ),
          onPressed: completed ||
                  rejected ||
                  !_canCompleteOrReject ||
                  _isCompleting ||
                  _isRejecting
              ? null
              : _completeInquiry,
          icon: _isCompleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(completed ? Icons.verified_rounded : Icons.check_circle_outline),
          label: Text(completed ? 'Completed' : 'Mark as Completed'),
        );
        final editButton = FilledButton.icon(
          onPressed: completed || rejected || !_canEditInquiry
              ? null
              : _editInquiry,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit Inquiry'),
        );
        final rejectButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF9F1239),
            foregroundColor: Colors.white,
          ),
          onPressed: rejected ||
                  !_canRejectInquiry ||
                  _isRejecting ||
                  _isCompleting
              ? null
              : _rejectInquiry,
          icon: _isRejecting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(rejected ? Icons.block_rounded : Icons.cancel_outlined),
          label: Text(rejected ? 'Rejected' : 'Reject Inquiry'),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 50, child: rejectButton),
              const SizedBox(height: 10),
              SizedBox(height: 50, child: completeButton),
              const SizedBox(height: 10),
              SizedBox(height: 50, child: editButton),
              const SizedBox(height: 10),
              SizedBox(height: 50, child: backButton),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(width: 140, height: 50, child: backButton),
            const SizedBox(width: 12),
            SizedBox(width: 170, height: 50, child: rejectButton),
            const SizedBox(width: 12),
            SizedBox(width: 170, height: 50, child: editButton),
            const SizedBox(width: 12),
            SizedBox(width: 210, height: 50, child: completeButton),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 500 ? 14 : 20),
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _InfoData {
  final String label;
  final String value;
  final IconData icon;

  const _InfoData(this.label, this.value, this.icon);
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  final _InfoData data;

  const _InfoField({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 180;
        return Container(
          constraints: BoxConstraints(minHeight: compact ? 64 : 72),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          data.icon,
                          size: 17,
                          color: const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            data.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      data.icon,
                      size: 20,
                      color: const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            data.label,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _EmptyItems extends StatelessWidget {
  const _EmptyItems();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 42, color: Color(0xFF94A3B8)),
          SizedBox(height: 10),
          Text(
            'No items are attached to this inquiry.',
            style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              const Icon(Icons.cloud_off_rounded, size: 56, color: Color(0xFF94A3B8)),
              const SizedBox(height: 16),
              const Text(
                'Unable to load inquiry',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
