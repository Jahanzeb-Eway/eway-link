import '../models/inquiry.dart';

class InquiryService {
  static final InquiryService instance = InquiryService._internal();

  InquiryService._internal();

  factory InquiryService() => instance;

  final List<Inquiry> _inquiries = [];

  List<Inquiry> getAllInquiries() {
    return _inquiries;
  }

  void addInquiry(Inquiry inquiry) {
    _inquiries.add(inquiry);
  }

  void updateInquiry(int index, Inquiry inquiry) {
    _inquiries[index] = inquiry;
  }

  void deleteInquiry(int index) {
    _inquiries.removeAt(index);
  }

  void completeInquiry(int index) {
    final old = _inquiries[index];

    _inquiries[index] = Inquiry(
      id: old.id,
      customer: old.customer,
      address: old.address,
      coordinator: old.coordinator,
      dueDate: old.dueDate,
      status: "Completed",
      remarks: old.remarks,
      grandTotal: old.grandTotal,
      items: _inquiries[index].items,
    );
  }
}