import '../models/vendor.dart';
import '../services/supabase_service.dart';

class VendorRepository {
  VendorRepository._();

  static final VendorRepository instance =
      VendorRepository._();

  final db = SupabaseService.client;

  Future<VendorModel?> findByName(
      String vendorName) async {
    final data = await db
        .from('vendors')
        .select()
        .ilike(
          'vendor_name',
          vendorName.trim(),
        )
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return VendorModel.fromJson(data);
  }

  Future<VendorModel> create({
    required String vendorName,
    String? address,
    String? phone,
    String? email,
  }) async {
    final data = await db
        .from('vendors')
        .insert({
          'vendor_name': vendorName.trim(),
          'address': address,
          'phone': phone,
          'email': email,
        })
        .select()
        .single();

    return VendorModel.fromJson(data);
  }

  Future<VendorModel> getOrCreate({
    required String vendorName,
    String? address,
    String? phone,
    String? email,
  }) async {
    final existing =
        await findByName(vendorName);

    if (existing != null) {
      return existing;
    }

    return create(
      vendorName: vendorName,
      address: address,
      phone: phone,
      email: email,
    );
  }

  Future<List<VendorModel>> search(
      String keyword) async {
    final data = await db
        .from('vendors')
        .select()
        .ilike(
          'vendor_name',
          '${keyword.trim()}%',
        )
        .order('vendor_name')
        .limit(20);

    return data
        .map<VendorModel>(
          (e) => VendorModel.fromJson(e),
        )
        .toList();
  }
}