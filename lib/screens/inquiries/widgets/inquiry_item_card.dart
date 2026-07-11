import 'package:flutter/material.dart';

class InquiryItemCard extends StatefulWidget {
  const InquiryItemCard({super.key});

  @override
  State<InquiryItemCard> createState() => _InquiryItemCardState();
}

class _InquiryItemCardState extends State<InquiryItemCard> {
  final TextEditingController itemController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController vendorController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController previousRateController =
      TextEditingController();
  final TextEditingController totalController = TextEditingController();

  @override
  void dispose() {
    itemController.dispose();
    quantityController.dispose();
    vendorController.dispose();
    rateController.dispose();
    previousRateController.dispose();
    totalController.dispose();
    super.dispose();
  }

  void calculateTotal() {
    final qty = double.tryParse(quantityController.text) ?? 0;
    final rate = double.tryParse(rateController.text) ?? 0;

    totalController.text = (qty * rate).toStringAsFixed(2);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            Row(
              children: [

                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: itemController,
                    decoration: const InputDecoration(
                      labelText: "Item Name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(width: 15),

                Expanded(
                  child: TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Qty",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => calculateTotal(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            Row(
              children: [

                Expanded(
                  child: TextField(
                    controller: vendorController,
                    decoration: const InputDecoration(
                      labelText: "Vendor",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(width: 15),

                Expanded(
                  child: TextField(
                    controller: rateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Rate",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => calculateTotal(),
                  ),
                ),

                const SizedBox(width: 15),

                Expanded(
                  child: TextField(
                    controller: previousRateController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: "Previous Rate",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(width: 15),

                Expanded(
                  child: TextField(
                    controller: totalController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: "Total",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}