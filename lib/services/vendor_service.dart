import '../utils/search_helper.dart';
import 'supabase_service.dart';

class VendorService {
  VendorService._();

  static final VendorService instance = VendorService._();

  Future<String> getOrCreateVendor({
    required String vendorName,
    String? address,
    String? phone,
    String? email,
  }) async {
    final db = SupabaseService.client;

    final searchName =
        SearchHelper.normalize(vendorName);

    final existing = await db
        .from('vendors')
        .select('id')
        .eq('search_name', searchName)
        .maybeSingle();

    if (existing != null) {
      return existing['id'];
    }

    final created = await db
        .from('vendors')
        .insert({
          'vendor_name': vendorName.trim(),
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