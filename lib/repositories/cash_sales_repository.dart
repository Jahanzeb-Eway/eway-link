import '../models/cash_sale.dart';
import '../services/supabase_service.dart';

class CashSalesRepository {
  CashSalesRepository._();

  static final CashSalesRepository instance = CashSalesRepository._();

  final db = SupabaseService.client;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> _relation(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return const {};
  }

  Future<String> nextSaleNumber() async {
    final response = await db.rpc('next_cash_sale_number');
    return response.toString();
  }

  Future<List<CashSale>> getSales() async {
    final response = await db.from('cash_sales').select('''
      id, sale_no, sales_person_name, status, grand_total,
      created_at, erp_entered_at,
      customers(customer_name, address)
    ''').order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response as List)
        .map(_saleFromHeader)
        .toList();
  }

  Future<CashSale> getSale(String id) async {
    final results = await Future.wait<dynamic>([
      db.from('cash_sales').select('''
        id, sale_no, sales_person_name, status, grand_total,
        created_at, erp_entered_at,
        customers(customer_name, address)
      ''').eq('id', id).single(),
      db.from('cash_sale_items').select('''
        id, qty, previous_rate, sales_rate, total,
        items(item_name), units(unit_name)
      ''').eq('cash_sale_id', id).order('created_at'),
    ]);

    final header = Map<String, dynamic>.from(results[0] as Map);
    final items = List<Map<String, dynamic>>.from(results[1] as List)
        .map((row) {
          final item = _relation(row, 'items');
          final unit = _relation(row, 'units');
          return CashSaleLine(
            id: row['id']?.toString() ?? '',
            itemName: item['item_name']?.toString() ?? '',
            unitName: unit['unit_name']?.toString() ?? '',
            quantity: _number(row['qty']),
            previousRate: _number(row['previous_rate']),
            salesRate: _number(row['sales_rate']),
            total: _number(row['total']),
          );
        })
        .toList();
    return _saleFromHeader(header, items: items);
  }

  CashSale _saleFromHeader(
    Map<String, dynamic> row, {
    List<CashSaleLine> items = const [],
  }) {
    final customer = _relation(row, 'customers');
    return CashSale(
      id: row['id']?.toString() ?? '',
      saleNumber: row['sale_no']?.toString() ?? '',
      customerName: customer['customer_name']?.toString() ?? '',
      customerAddress: customer['address']?.toString() ?? '',
      salesPersonName: row['sales_person_name']?.toString() ?? '',
      status: row['status']?.toString() ?? 'Completed',
      grandTotal: _number(row['grand_total']),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      erpEnteredAt:
          DateTime.tryParse(row['erp_entered_at']?.toString() ?? ''),
      items: items,
    );
  }

  Future<PreviousCustomerSale?> getPreviousCustomerSale({
    required String customerId,
    required String itemName,
  }) async {
    if (customerId.isEmpty || itemName.trim().isEmpty) return null;
    final response = await db.rpc(
      'get_last_customer_item_sale',
      params: {
        'p_customer_id': customerId,
        'p_item_name': itemName.trim(),
      },
    );
    final rows = List<Map<String, dynamic>>.from(response as List);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PreviousCustomerSale(
      rate: _number(row['sales_rate']),
      unitName: row['unit_name']?.toString() ?? '',
      soldAt: DateTime.tryParse(row['sold_at']?.toString() ?? ''),
    );
  }

  Future<String> createSale({
    required String saleNumber,
    required String customerId,
    required String salesPersonName,
    required List<CashSaleLineInput> items,
  }) async {
    final result = await db.rpc(
      'create_cash_sale',
      params: {
        'p_sale_no': saleNumber,
        'p_customer_id': customerId,
        'p_sales_person_name': salesPersonName,
        'p_items': items
            .map(
              (item) => {
                'item_id': item.itemId,
                'unit_id': item.unitId,
                'quantity': item.quantity,
                'previous_rate': item.previousRate,
                'sales_rate': item.salesRate,
              },
            )
            .toList(),
      },
    );
    return result.toString();
  }

  Future<void> markEnteredIntoErp(String saleId) async {
    await db
        .from('cash_sales')
        .update({'status': 'Entered into ERP'})
        .eq('id', saleId);
  }
}
