class CustomerModel {
  final String id;
  final String customerName;
  final String? address;
  final String? phone;
  final String? email;
  final String? ntn;

  const CustomerModel({
    required this.id,
    required this.customerName,
    this.address,
    this.phone,
    this.email,
    this.ntn,
  });

  factory CustomerModel.fromJson(
      Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as String,
      customerName: json['customer_name'] as String,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      ntn: json['ntn'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_name': customerName,
      'address': address,
      'phone': phone,
      'email': email,
      'ntn': ntn,
    };
  }
}