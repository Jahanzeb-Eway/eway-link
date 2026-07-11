import 'inquiry_item.dart';

class Inquiry {

  final String id;
  final String customer;
  final String address;
  final String coordinator;
  final String dueDate;
  final String status;
  final String remarks;
  final double grandTotal;

  final List<InquiryItem> items;

  Inquiry({

    required this.id,

    required this.customer,

    required this.address,

    required this.coordinator,

    required this.dueDate,

    required this.status,

    required this.remarks,

    required this.grandTotal,

    required this.items,

  });

}