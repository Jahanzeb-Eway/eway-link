import '../models/unit.dart';
import '../services/supabase_service.dart';

class UnitRepository {
  UnitRepository._();

  static final UnitRepository instance =
      UnitRepository._();

  final db = SupabaseService.client;

  Future<UnitModel?> findByName(
      String unitName) async {

    final data = await db
        .from('units')
        .select()
        .ilike(
          'unit_name',
          unitName.trim(),
        )
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return UnitModel.fromJson(data);
  }

  Future<UnitModel> getByName(
      String unitName) async {

    final unit =
        await findByName(unitName);

    if (unit == null) {
      throw Exception(
        'Unit "$unitName" does not exist.',
      );
    }

    return unit;
  }

  Future<List<UnitModel>> getAll() async {

    final data = await db
        .from('units')
        .select()
        .order('unit_name');

    return data
        .map<UnitModel>(
          (e) => UnitModel.fromJson(e),
        )
        .toList();
  }
}