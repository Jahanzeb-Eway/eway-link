class VendorModel {
  final String id;
  final String vendorName;
  final String? address;
  final String? phone;
  final String? email;

  const VendorModel({
    required this.id,
    required this.vendorName,
    this.address,
    this.phone,
    this.email,
  });

  factory VendorModel.fromJson(
      Map<String, dynamic> json) {
    return VendorModel(
      id: json['id'] as String,
      vendorName: json['vendor_name'] as String,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vendor_name': vendorName,
      'address': address,
      'phone': phone,
      'email': email,
    };
  }
}