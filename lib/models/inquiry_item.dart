class InquiryItem {
  final String itemName;
  final double qty;
  final String unit;
  final String vendor;
  final double previousRate;
  final double rate;
  final double total;

  InquiryItem({
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.vendor,
    required this.previousRate,
    required this.rate,
    required this.total,
  });
}