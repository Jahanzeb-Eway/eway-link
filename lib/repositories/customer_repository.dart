import '../models/customer.dart';
import '../services/supabase_service.dart';

class CustomerRepository {
  CustomerRepository._();

  static final CustomerRepository instance =
      CustomerRepository._();

  final db = SupabaseService.client;

  Future<CustomerModel?> findByName(
      String customerName) async {
    final data = await db
        .from('customers')
        .select()
        .ilike(
          'customer_name',
          customerName.trim(),
        )
        .maybeSingle();

    if (data == null) return null;

    return CustomerModel.fromJson(data);
  }

  Future<CustomerModel> create({
    required String customerName,
    String? address,
    String? phone,
    String? email,
    String? ntn,
  }) async {
    final data = await db
        .from('customers')
        .insert({
          'customer_name': customerName.trim(),
          'address': address,
          'phone': phone,
          'email': email,
          'ntn': ntn,
        })
        .select()
        .single();

    return CustomerModel.fromJson(data);
  }

  Future<CustomerModel> getOrCreate({
    required String customerName,
    String? address,
    String? phone,
    String? email,
    String? ntn,
  }) async {
    final existing =
        await findByName(customerName);

    if (existing != null) {
      return existing;
    }

    return create(
      customerName: customerName,
      address: address,
      phone: phone,
      email: email,
      ntn: ntn,
    );
  }

  Future<List<CustomerModel>> search(
      String keyword) async {
    final data = await db
        .from('customers')
        .select()
        .ilike(
          'customer_name',
          '${keyword.trim()}%',
        )
        .order('customer_name')
        .limit(20);

    return data
        .map<CustomerModel>(
          (e) => CustomerModel.fromJson(e),
        )
        .toList();
  }

  Future<List<CustomerModel>> getAll() async {
    final data = await db
        .from('customers')
        .select()
        .order('customer_name');

    return data
        .map<CustomerModel>(
          (e) => CustomerModel.fromJson(e),
        )
        .toList();
  }
}
