class CashSaleLine {
  final String id;
  final String itemName;
  final String unitName;
  final double quantity;
  final double previousRate;
  final double salesRate;
  final double total;

  const CashSaleLine({
    required this.id,
    required this.itemName,
    required this.unitName,
    required this.quantity,
    required this.previousRate,
    required this.salesRate,
    required this.total,
  });
}

class CashSale {
  final String id;
  final String saleNumber;
  final String customerName;
  final String customerAddress;
  final String salesPersonName;
  final String status;
  final double grandTotal;
  final DateTime createdAt;
  final DateTime? erpEnteredAt;
  final List<CashSaleLine> items;

  const CashSale({
    required this.id,
    required this.saleNumber,
    required this.customerName,
    required this.customerAddress,
    required this.salesPersonName,
    required this.status,
    required this.grandTotal,
    required this.createdAt,
    required this.erpEnteredAt,
    required this.items,
  });

  bool get isEnteredIntoErp => status == 'Entered into ERP';
}

class CashSaleLineInput {
  final String itemId;
  final String unitId;
  final double quantity;
  final double previousRate;
  final double salesRate;

  const CashSaleLineInput({
    required this.itemId,
    required this.unitId,
    required this.quantity,
    required this.previousRate,
    required this.salesRate,
  });

  double get total => quantity * salesRate;
}

class PreviousCustomerSale {
  final double rate;
  final String unitName;
  final DateTime? soldAt;

  const PreviousCustomerSale({
    required this.rate,
    required this.unitName,
    required this.soldAt,
  });
}
