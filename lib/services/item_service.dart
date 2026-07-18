import '../utils/search_helper.dart';
import 'supabase_service.dart';

class ItemService {
  ItemService._();

  static final ItemService instance = ItemService._();

  Future<String> getOrCreateItem({
    required String itemName,
    required String unitName,
    String? category,
    String? remarks,
  }) async {
    final db = SupabaseService.client;

    final searchName = SearchHelper.normalize(itemName);

    // Find Unit
    final unit = await db
        .from('units')
        .select('id')
        .eq('unit_name', unitName.trim().toUpperCase())
        .single();

    final unitId = unit['id'] as String;

    // Search existing item
    final existing = await db
        .from('items')
        .select('id')
        .eq('search_name', searchName)
        .maybeSingle();

    if (existing != null) {
      return existing['id'] as String;
    }

    // Create item
    final created = await db
        .from('items')
        .insert({
          'item_name': itemName.trim(),
          'search_name': searchName,
          'default_unit_id': unitId,
          'category': category,
          'remarks': remarks,
        })
        .select('id')
        .single();

    return created['id'] as String;
  }

  Future<List<Map<String, dynamic>>> searchItems(
      String keyword) async {
    final db = SupabaseService.client;

    final search = SearchHelper.normalize(keyword);

    if (search.isEmpty) {
      return [];
    }

    final data = await db
        .from('items')
        .select('id, item_name, default_unit_id')
        .ilike('search_name', '$search%')
        .order('item_name')
        .limit(15);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> getItem(
      String itemId) async {
    final db = SupabaseService.client;

    return await db
        .from('items')
        .select()
        .eq('id', itemId)
        .maybeSingle();
  }
}