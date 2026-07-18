import 'package:flutter/material.dart';

class InquiryTableController {
  _InquiryTableState? _state;

  List<InquiryLine> get lines {
    return _state?.lines ?? [];
  }

  double get grandTotal {
    return _state?._grandTotal ?? 0;
  }

  void addRow() {
    _state?.addRow();
  }

  void clear() {
    _state?.clearTable();
  }
}

class InquiryTable extends StatefulWidget {

  final ValueChanged<double> onGrandTotalChanged;

  final InquiryTableController controller;

  const InquiryTable({
    super.key,
    required this.controller,
    required this.onGrandTotalChanged,
  });

  @override
  State<InquiryTable> createState() =>
      _InquiryTableState();
}

class InquiryLine {

  final itemController = TextEditingController();

  final qtyController = TextEditingController();

  final unitController = TextEditingController(text: "PCS");

  final vendorController = TextEditingController();

  final previousRateController =
      TextEditingController(text: "0.00");

  final rateController =
      TextEditingController();

  double total = 0;

  void dispose() {

    itemController.dispose();

    qtyController.dispose();

    unitController.dispose();

    vendorController.dispose();

    previousRateController.dispose();

    rateController.dispose();

  }

}

class _InquiryTableState
    extends State<InquiryTable> {

  //------------------------
  // Column Widths
  //------------------------

  static const double noWidth = 60;

  static const double itemWidth = 340;

  static const double qtyWidth = 90;

  static const double unitWidth = 90;

  static const double vendorWidth = 240;

  static const double previousWidth = 150;

  static const double rateWidth = 120;

  static const double totalWidth = 150;

  static const double deleteWidth = 60;

  static const double rowHeight = 54;

  //------------------------

  final List<InquiryLine> lines = [];

double _grandTotal = 0;

  final List<String> units = [
  "PCS",
  "KG",
  "GRAM",
  "LITER",
  "ML",
  "METER",
  "FEET",
  "BOX",
  "ROLL",
  "SET",
  "PAIR",
  "BAG",
  "DRUM",
  "TON",
];

@override
void initState() {
  super.initState();

  widget.controller._state = this;

  addRow();
}

  @override
  void dispose() {

    for (final line in lines) {

      line.dispose();

    }

    super.dispose();

  }

  void addRow() {

    lines.add(InquiryLine());

    setState(() {});

  }

  void removeRow(int index) {

    if (lines.length == 1) return;

    lines[index].dispose();

    lines.removeAt(index);

    calculateGrandTotal();

    setState(() {});

  }

  void calculateRow(int index) {

    final qty = double.tryParse(
          lines[index].qtyController.text,
        ) ??
        0;

    final rate = double.tryParse(
          lines[index].rateController.text,
        ) ??
        0;

    lines[index].total = qty * rate;

    calculateGrandTotal();

    setState(() {});

  }

void calculateGrandTotal() {

  _grandTotal = 0;

  for (final line in lines) {
    _grandTotal += line.total;
  }

  widget.onGrandTotalChanged(
    _grandTotal,
  );
}

void clearTable() {

  for (final line in lines) {

    line.itemController.clear();

    line.qtyController.clear();

    line.unitController.text = "PCS";

    line.vendorController.clear();

    line.previousRateController.text = "0.00";

    line.rateController.clear();

    line.total = 0;
  }

  calculateGrandTotal();

  setState(() {});
}

    //====================================================
  // ERP GRID CONTROLS
  //====================================================

  Widget headerCell(
    String title,
    double width,
  ) {
    return Container(
      width: width,
      height: rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xff1E293B),
        border: Border.all(
          color: Colors.white24,
        ),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget textCell({
    required TextEditingController controller,
    required double width,
    bool readOnly = false,
    TextInputType keyboardType =
        TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      width: width,
      height: rowHeight,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 13,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

Widget unitCell({
  required InquiryLine line,
}) {
  return Container(
    width: unitWidth,
    height: rowHeight,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      border: Border.all(
        color: Colors.grey.shade300,
      ),
    ),
    child: DropdownButtonFormField<String>(
      initialValue: line.unitController.text,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 10,
        ),
      ),
      items: units.map((unit) {
        return DropdownMenuItem<String>(
          value: unit,
          child: Text(
            unit,
            style: const TextStyle(fontSize: 13),
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            line.unitController.text = value;
          });
        }
      },
    ),
  );
}

  Widget totalCell(double total) {
    return Container(
      width: totalWidth,
      height: rowHeight,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Container(
        alignment: Alignment.centerRight,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius:
              BorderRadius.circular(4),
        ),
        child: Text(
          total.toStringAsFixed(2),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget deleteCell(int index) {
    return Container(
      width: deleteWidth,
      height: rowHeight,
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: IconButton(
        splashRadius: 18,
        icon: const Icon(
          Icons.delete_outline,
          color: Colors.red,
        ),
        onPressed: () {
          removeRow(index);
        },
      ),
    );
  }

  Widget buildHeader() {
    return Row(
      children: [

        headerCell("#", noWidth),

        headerCell(
          "Item Name",
          itemWidth,
        ),

headerCell(
  "Qty",
  qtyWidth,
),

headerCell(
  "Unit",
  unitWidth,
),

headerCell(
  "Vendor",
  vendorWidth,
),

        headerCell(
          "Previous",
          previousWidth,
        ),

        headerCell(
          "Rate",
          rateWidth,
        ),

        headerCell(
          "Total",
          totalWidth,
        ),

        headerCell(
          "",
          deleteWidth,
        ),

      ],
    );
  }

    Widget buildRow(
    int index,
    InquiryLine line,
  ) {
    return Container(
      color: index.isEven
          ? Colors.white
          : const Color(0xffFAFBFC),
      child: Row(
        children: [

          // Row Number
          Container(
            width: noWidth,
            height: rowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey.shade300,
              ),
            ),
            child: Text(
              "${index + 1}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Item Name
          textCell(
            controller: line.itemController,
            width: itemWidth,
          ),

// Quantity
textCell(
  controller: line.qtyController,
  width: qtyWidth,
  keyboardType: TextInputType.number,
  onChanged: (_) {
    calculateRow(index);
  },
),

// Unit
unitCell(
  line: line,
),

// Vendor
textCell(
  controller: line.vendorController,
  width: vendorWidth,
),

          // Previous Rate
          textCell(
            controller:
                line.previousRateController,
            width: previousWidth,
            readOnly: true,
          ),

          // Rate
          textCell(
            controller: line.rateController,
            width: rateWidth,
            keyboardType: TextInputType.number,
            onChanged: (_) {
              calculateRow(index);
            },
          ),

          // Total
          totalCell(line.total),

          // Delete
          deleteCell(index),

        ],
      ),
    );
  }

  Widget buildGrid() {
    return Column(
      children: List.generate(
        lines.length,
        (index) =>
            buildRow(index, lines[index]),
      ),
    );
  }
    @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            //========================
            // GRID
            //========================

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [

                  buildHeader(),

                  buildGrid(),

                ],
              ),
            ),

            const SizedBox(height: 20),

            //========================
            // FOOTER
            //========================

            Row(
              children: [

                ElevatedButton.icon(
                  onPressed: addRow,
                  icon: const Icon(Icons.add),
                  label: const Text(
                    "Add Item",
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize:
                        const Size(140, 48),
                  ),
                ),

                const SizedBox(width: 12),

OutlinedButton.icon(
  onPressed: clearTable,
  icon: const Icon(Icons.refresh),
  label: const Text("Clear All"),
  style: OutlinedButton.styleFrom(
    minimumSize: const Size(140, 48),
  ),
),

                const Spacer(),

                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xffF8FAFC),
                    borderRadius:
                        BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [

                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                      ),

                      const SizedBox(width: 8),

                      const Text(
                        "Items",
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(width: 10),

                      Text(
                        "${lines.length}",
                        style:
                            const TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                    ],
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
