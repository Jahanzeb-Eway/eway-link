class UnitModel {
  final String id;
  final String unitName;
  final String symbol;
  final bool isActive;

  UnitModel({
    required this.id,
    required this.unitName,
    required this.symbol,
    required this.isActive,
  });

  factory UnitModel.fromJson(
      Map<String, dynamic> json) {
    return UnitModel(
      id: json['id'],
      unitName: json['unit_name'],
      symbol: json['symbol'] ?? '',
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'unit_name': unitName,
      'symbol': symbol,
      'is_active': isActive,
    };
  }
}