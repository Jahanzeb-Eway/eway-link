class ItemModel {
  final String id;
  final String itemName;
  final String? defaultUnitId;
  final String? category;
  final String? remarks;

  const ItemModel({
    required this.id,
    required this.itemName,
    this.defaultUnitId,
    this.category,
    this.remarks,
  });

  factory ItemModel.fromJson(
      Map<String, dynamic> json) {
    return ItemModel(
      id: json['id'] as String,
      itemName: json['item_name'] as String,
      defaultUnitId:
          json['default_unit_id'] as String?,
      category: json['category'] as String?,
      remarks: json['remarks'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'item_name': itemName,
      'default_unit_id': defaultUnitId,
      'category': category,
      'remarks': remarks,
    };
  }
}