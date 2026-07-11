import 'package:flutter/material.dart';

class InquiryTable extends StatefulWidget {
  final ValueChanged<double> onTotalChanged;

  const InquiryTable({
    super.key,
    required this.onTotalChanged,
  });

  @override
  State<InquiryTable> createState() => _InquiryTableState();
}

class _InquiryTableState extends State<InquiryTable> {
  final List<_InquiryRow> rows = [];

  @override
  void initState() {
    super.initState();
    addRow();
  }

  void addRow() {
    rows.add(
      _InquiryRow(
        key: UniqueKey(),
        onChanged: calculateGrandTotal,
        onDelete: () {},
      ),
    );

    setState(() {});
  }

  void deleteRow(int index) {
    rows.removeAt(index);

    calculateGrandTotal();

    setState(() {});
  }

  void calculateGrandTotal() {
    double total = 0;

    for (final row in rows) {
      total += row.total;
    }

    widget.onTotalChanged(total);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        Container(
          color: Colors.blueGrey.shade100,
          padding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 10,
          ),
          child: const Row(
            children: [

              Expanded(flex: 3, child: Text("Item")),
              Expanded(child: Text("Qty")),
              Expanded(flex: 2, child: Text("Vendor")),
              Expanded(child: Text("Prev.")),
              Expanded(child: Text("Rate")),
              Expanded(child: Text("Total")),
              SizedBox(width: 50),

            ],
          ),
        ),

        const SizedBox(height: 8),

        ...List.generate(
          rows.length,
          (index) {
            rows[index].onDelete = () {
              deleteRow(index);
            };

            return rows[index];
          },
        ),

        const SizedBox(height: 15),

        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            onPressed: addRow,
            icon: const Icon(Icons.add),
            label: const Text("Add Item"),
          ),
        ),

      ],
    );
  }
}

class _InquiryRow extends StatefulWidget {
  VoidCallback onChanged;
  VoidCallback onDelete;

  double total = 0;

  _InquiryRow({
    super.key,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_InquiryRow> createState() => _InquiryRowState();
}

class _InquiryRowState extends State<_InquiryRow> {
  final item = TextEditingController();
  final qty = TextEditingController();
  final vendor = TextEditingController();
  final previousRate = TextEditingController();
  final rate = TextEditingController();
  final total = TextEditingController();

  @override
  void initState() {
    super.initState();

    qty.addListener(calculate);
    rate.addListener(calculate);

    previousRate.text = "0.00";
  }

  void calculate() {
    double q = double.tryParse(qty.text) ?? 0;
    double r = double.tryParse(rate.text) ?? 0;

    widget.total = q * r;

    total.text = widget.total.toStringAsFixed(2);

    widget.onChanged();

    setState(() {});
  }

  InputDecoration decoration(String text) {
    return InputDecoration(
      labelText: text,
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [

          Expanded(
            flex: 3,
            child: TextField(
              controller: item,
              decoration: decoration("Item"),
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: TextField(
              controller: qty,
              keyboardType: TextInputType.number,
              decoration: decoration("Qty"),
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            flex: 2,
            child: TextField(
              controller: vendor,
              decoration: decoration("Vendor"),
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: TextField(
              controller: previousRate,
              readOnly: true,
              decoration: decoration("Previous"),
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: TextField(
              controller: rate,
              keyboardType: TextInputType.number,
              decoration: decoration("Rate"),
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: TextField(
              controller: total,
              readOnly: true,
              decoration: decoration("Total"),
            ),
          ),

          IconButton(
            onPressed: widget.onDelete,
            icon: const Icon(
              Icons.delete,
              color: Colors.red,
            ),
          ),

        ],
      ),
    );
  }
}