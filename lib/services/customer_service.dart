import '../utils/search_helper.dart';
import 'supabase_service.dart';

class CustomerService {
  CustomerService._();

  static final CustomerService instance = CustomerService._();

  Future<String> getOrCreateCustomer({
    required String customerName,
    String? address,
    String? phone,
    String? email,
  }) async {
    final db = SupabaseService.client;

    final searchName =
        SearchHelper.normalize(customerName);

    final existing = await db
        .from('customers')
        .select('id')
        .eq('search_name', searchName)
        .maybeSingle();

    if (existing != null) {
      return existing['id'];
    }

    final created = await db
        .from('customers')
        .insert({
          'customer_name': customerName.trim(),
          'search_name': searchName,
          'address': address,
          'phone': phone,
          'email': email,
        })
        .select('id')
        .single();

    return created['id'];
  }
}