import '../services/supabase_service.dart';

class LastPurchaseInfo {
  final String vendorName;
  final String unitName;
  final double rate;
  final DateTime? purchasedAt;

  const LastPurchaseInfo({
    required this.vendorName,
    required this.unitName,
    required this.rate,
    required this.purchasedAt,
  });
}

class InquiryRepository {
  InquiryRepository._();

  static final InquiryRepository instance =
      InquiryRepository._();

  final db = SupabaseService.client;

  //==========================================
  // LAST PURCHASE BY ITEM NAME
  //==========================================

  Future<LastPurchaseInfo?> getLastPurchaseForItem(
    String itemName,
  ) async {
    final normalizedName = itemName.trim();
    if (normalizedName.isEmpty) return null;

    final response = await db
        .from('inquiry_items')
        .select('''
          selected_rate,
          items!inner(item_name),
          vendors(vendor_name),
          units(unit_name),
          inquiries(created_at)
        ''')
        .ilike('items.item_name', normalizedName);

    final rows = List<Map<String, dynamic>>.from(
      (response as List).map(
        (row) => Map<String, dynamic>.from(row as Map),
      ),
    );
    if (rows.isEmpty) return null;

    DateTime? inquiryDate(Map<String, dynamic> row) {
      final relation = row['inquiries'];
      dynamic rawDate;
      if (relation is Map) {
        rawDate = relation['created_at'];
      } else if (relation is List && relation.isNotEmpty) {
        rawDate = (relation.first as Map)['created_at'];
      }
      return DateTime.tryParse(rawDate?.toString() ?? '');
    }

    rows.sort((first, second) {
      final firstDate = inquiryDate(first);
      final secondDate = inquiryDate(second);
      if (firstDate == null && secondDate == null) return 0;
      if (firstDate == null) return 1;
      if (secondDate == null) return -1;
      return secondDate.compareTo(firstDate);
    });

    final latest = rows.first;
    String relationText(String key, String field) {
      final relation = latest[key];
      if (relation is Map) {
        return relation[field]?.toString().trim() ?? '';
      }
      if (relation is List && relation.isNotEmpty && relation.first is Map) {
        return (relation.first as Map)[field]?.toString().trim() ?? '';
      }
      return '';
    }

    final rateValue = latest['selected_rate'];
    final rate = rateValue is num
        ? rateValue.toDouble()
        : double.tryParse(rateValue?.toString() ?? '') ?? 0;

    return LastPurchaseInfo(
      vendorName: relationText('vendors', 'vendor_name'),
      unitName: relationText('units', 'unit_name'),
      rate: rate,
      purchasedAt: inquiryDate(latest),
    );
  }

  //==========================================
  // CREATE INQUIRY
  //==========================================

  Future<String> createInquiry({
    required String inquiryNo,
    required String customerId,
    required String coordinatorId,
    required String coordinator,
    required DateTime dueDate,
    required String status,
    required double grandTotal,
    String? createdBy,
  }) async {
    final result = await db
        .from('inquiries')
        .insert({
          'inquiry_no': inquiryNo,
          'customer_id': customerId,
          'coordinator_id': coordinatorId,
          'coordinator': coordinator,
          'due_date': dueDate.toIso8601String(),
          'status': status,
          'grand_total': grandTotal,
          'created_by': createdBy ?? db.auth.currentUser?.id,
        })
        .select('id')
        .single();

    return result['id'] as String;
  }

  //==========================================
  // SAVE INQUIRY ITEM
  //==========================================

  Future<void> saveInquiryItem({
    required String inquiryId,
    required String itemId,
    required String unitId,
    String? vendorId,
    required double qty,
    required double previousRate,
    required double selectedRate,
    required double total,
  }) async {
    await db
        .from('inquiry_items')
        .insert({
          'inquiry_id': inquiryId,
          'item_id': itemId,
          'qty': qty,
          'unit_id': unitId,
          'selected_vendor_id': vendorId,
          'previous_rate': previousRate,
          'selected_rate': selectedRate,
          'total': total,
        });
  }

  Future<void> updateInquiryItemQuote({
    required String inquiryItemId,
    required String vendorId,
    required double selectedRate,
    required double total,
  }) async {
    await db
        .from('inquiry_items')
        .update({
          'selected_vendor_id': vendorId,
          'selected_rate': selectedRate,
          'total': total,
        })
        .eq('id', inquiryItemId);
  }

  Future<void> updateInquiryPricing({
    required String inquiryId,
    required double grandTotal,
    required String status,
  }) async {
    await db
        .from('inquiries')
        .update({
          'grand_total': grandTotal,
          'status': status,
        })
        .eq('id', inquiryId);
  }

  //==========================================
  // UPDATE INQUIRY
  //==========================================

  Future<void> updateInquiry({
    required String inquiryId,
    required String customerId,
    required String coordinatorId,
    required String coordinator,
    required DateTime dueDate,
    required String status,
    required double grandTotal,
  }) async {
    await db
        .from('inquiries')
        .update({
          'customer_id': customerId,
          'coordinator_id': coordinatorId,
          'coordinator': coordinator,
          'due_date': dueDate.toIso8601String(),
          'status': status,
          'grand_total': grandTotal,
        })
        .eq('id', inquiryId);
  }

  //==========================================
  // DELETE ITEMS
  //==========================================

  Future<void> deleteInquiryItems(
      String inquiryId) async {
    await db
        .from('inquiry_items')
        .delete()
        .eq('inquiry_id', inquiryId);
  }

  //==========================================
  // DELETE INQUIRY
  //==========================================

  Future<void> deleteInquiry(
      String inquiryId) async {
    await db
        .from('inquiries')
        .delete()
        .eq('id', inquiryId);
  }

  //==========================================
  // COMPLETE
  //==========================================

  Future<void> completeInquiry(
      String inquiryId) async {
    final items = await db
        .from('inquiry_items')
        .select('selected_vendor_id, selected_rate')
        .eq('inquiry_id', inquiryId);

    final rows = List<Map<String, dynamic>>.from(
      (items as List).map(
        (row) => Map<String, dynamic>.from(row as Map),
      ),
    );
    final incomplete = rows.isEmpty || rows.any((row) {
      final vendorId = row['selected_vendor_id']?.toString().trim() ?? '';
      final rawRate = row['selected_rate'];
      final rate = rawRate is num
          ? rawRate.toDouble()
          : double.tryParse(rawRate?.toString() ?? '') ?? 0;
      return vendorId.isEmpty || rate <= 0;
    });
    if (incomplete) {
      throw StateError(
        'Every item requires a vendor and rate before completion.',
      );
    }

    await db
        .from('inquiries')
        .update({
          'status': 'Completed',
        })
        .eq('id', inquiryId);
  }

  //==========================================
  // REJECT
  //==========================================

  Future<void> rejectInquiry(
      String inquiryId) async {
    await db
        .from('inquiries')
        .update({
          'status': 'Rejected',
        })
        .eq('id', inquiryId);
  }
}
