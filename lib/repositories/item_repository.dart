import '../models/item.dart';
import '../services/supabase_service.dart';

class ItemRepository {
  ItemRepository._();

  static final ItemRepository instance =
      ItemRepository._();

  final db = SupabaseService.client;

  Future<ItemModel?> findByName(
      String itemName) async {

    final data = await db
        .from('items')
        .select()
        .ilike(
          'item_name',
          itemName.trim(),
        )
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return ItemModel.fromJson(data);
  }

  Future<ItemModel> create({
    required String itemName,
    required String unitId,
    String? category,
    String? remarks,
  }) async {

    final data = await db
        .from('items')
        .insert({
          'item_name': itemName.trim(),
          'default_unit_id': unitId,
          'category': category,
          'remarks': remarks,
        })
        .select()
        .single();

    return ItemModel.fromJson(data);
  }

  Future<ItemModel> getOrCreate({
    required String itemName,
    required String unitId,
    String? category,
    String? remarks,
  }) async {

    final existing =
        await findByName(itemName);

    if (existing != null) {
      return existing;
    }

    return create(
      itemName: itemName,
      unitId: unitId,
      category: category,
      remarks: remarks,
    );
  }

  Future<List<ItemModel>> search(
      String keyword) async {

    final data = await db
        .from('items')
        .select()
        .ilike(
          'item_name',
          '${keyword.trim()}%',
        )
        .order('item_name')
        .limit(20);

    return data
        .map<ItemModel>(
          (e) => ItemModel.fromJson(e),
        )
        .toList();
  }

  Future<List<ItemModel>> getAll() async {
    final data = await db
        .from('items')
        .select()
        .order('item_name');

    return data
        .map<ItemModel>(
          (e) => ItemModel.fromJson(e),
        )
        .toList();
  }

  Future<ItemModel?> getById(
      String id) async {

    final data = await db
        .from('items')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return ItemModel.fromJson(data);
  }
}
