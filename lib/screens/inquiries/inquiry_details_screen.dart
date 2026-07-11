import 'package:flutter/material.dart';

import '../../models/inquiry.dart';
import '../../models/inquiry_item.dart';
import '../../theme/app_colors.dart';

class InquiryDetailsScreen extends StatelessWidget {
  final Inquiry inquiry;

  const InquiryDetailsScreen({
    super.key,
    required this.inquiry,
  });

  Widget infoField({
    required String label,
    required String value,
    int flex = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Padding(
            padding: const EdgeInsets.only(
              left: 2,
              bottom: 6,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          Container(
            height: 48,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  BorderRadius.circular(10),
              border: Border.all(
                color: Colors.grey.shade300,
              ),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

        ],
      ),
    );
  }

  TableRow buildHeader() {

    Widget cell(String title) {

      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

    }

    return TableRow(

      decoration: const BoxDecoration(
        color: Color(0xff1E293B),
      ),

      children: [

        cell("Item Name"),

        cell("Qty"),

        cell("Vendor"),

        cell("Previous"),

        cell("Rate"),

        cell("Total"),

      ],

    );

  }

  TableRow buildItemRow(
    InquiryItem item,
  ) {

    Widget cell(String value) {

      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(value),
      );

    }

    return TableRow(

      children: [

        cell(item.itemName),

        cell(item.qty.toString()),

        cell(item.vendor),

        cell(item.previousRate
            .toStringAsFixed(2)),

        cell(item.rate
            .toStringAsFixed(2)),

        cell(item.total
            .toStringAsFixed(2)),

      ],

    );

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
          const Color(0xffF4F6F9),

      appBar: AppBar(

        backgroundColor:
            AppColors.primary,

        foregroundColor:
            Colors.white,

        title: const Text(
          "Inquiry Details",
        ),

      ),

      body: SingleChildScrollView(

        padding:
            const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            Container(

              padding:
                  const EdgeInsets.all(18),

              decoration: BoxDecoration(

                color: Colors.white,

                borderRadius:
                    BorderRadius.circular(16),

                boxShadow: const [

                  BoxShadow(

                    color: Colors.black12,

                    blurRadius: 8,

                  ),

                ],

              ),

              child: Column(

                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [

                  const Text(

                    "Customer Information",

                    style: TextStyle(

                      fontSize: 18,

                      fontWeight:
                          FontWeight.w600,

                    ),

                  ),

                  const SizedBox(height: 16),

                                    Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [

                      infoField(
                        label: "Customer Name",
                        value: inquiry.customer,
                        flex: 3,
                      ),

                      const SizedBox(width: 16),

                      infoField(
                        label: "Coordinator",
                        value: inquiry.coordinator,
                        flex: 2,
                      ),

                      const SizedBox(width: 16),

                      infoField(
                        label: "Inquiry No",
                        value: inquiry.id,
                        flex: 2,
                      ),

                    ],
                  ),

                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [

                      infoField(
                        label: "Customer Address",
                        value: inquiry.address,
                        flex: 5,
                      ),

                      const SizedBox(width: 16),

                      infoField(
                        label: "Due Date",
                        value: inquiry.dueDate,
                        flex: 2,
                      ),

                    ],
                  ),

                ],

              ),

            ),

            const SizedBox(height: 16),

            const Text(

              "Inquiry Items",

              style: TextStyle(

                fontSize: 20,

                fontWeight:
                    FontWeight.w600,

              ),

            ),

            const SizedBox(height: 10),

            Container(

              decoration: BoxDecoration(

                color: Colors.white,

                borderRadius:
                    BorderRadius.circular(16),

                boxShadow: const [

                  BoxShadow(

                    color: Colors.black12,

                    blurRadius: 8,

                  ),

                ],

              ),

              child: Table(

                border: TableBorder.all(
                  color: Colors.grey.shade300,
                ),

                columnWidths: const {

                  0: FlexColumnWidth(3),

                  1: FlexColumnWidth(1),

                  2: FlexColumnWidth(2),

                  3: FlexColumnWidth(2),

                  4: FlexColumnWidth(1.5),

                  5: FlexColumnWidth(1.5),

                },

                children: [

                  buildHeader(),

                  ...inquiry.items.map(
                    (item) =>
                        buildItemRow(item),
                  ),

                ],

              ),

            ),

            const SizedBox(height: 20),

                        Align(

              alignment: Alignment.centerRight,

              child: Container(

                width: 300,

                padding: const EdgeInsets.all(18),

                decoration: BoxDecoration(

                  color: Colors.white,

                  borderRadius:
                      BorderRadius.circular(16),

                  boxShadow: const [

                    BoxShadow(

                      color: Colors.black12,

                      blurRadius: 8,

                    ),

                  ],

                ),

                child: Column(

                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    const Text(

                      "Grand Total",

                      style: TextStyle(

                        fontSize: 18,

                        fontWeight:
                            FontWeight.bold,

                      ),

                    ),

                    const SizedBox(height: 10),

                    Text(

                      "PKR ${inquiry.grandTotal.toStringAsFixed(2)}",

                      style: const TextStyle(

                        fontSize: 28,

                        fontWeight:
                            FontWeight.bold,

                        color:
                            AppColors.primary,

                      ),

                    ),

                  ],

                ),

              ),

            ),

            const SizedBox(height: 30),

            Row(

              children: [

                Expanded(

                  child: SizedBox(

                    height: 52,

                    child: OutlinedButton.icon(

                      onPressed: () {

                        Navigator.pop(context);

                      },

                      icon: const Icon(
                        Icons.arrow_back,
                      ),

                      label: const Text(
                        "Back",
                      ),

                    ),

                  ),

                ),

                const SizedBox(width: 15),

                Expanded(

                  child: SizedBox(

                    height: 52,

                    child: ElevatedButton.icon(

                      style:
                          ElevatedButton.styleFrom(

                        backgroundColor:
                            AppColors.primary,

                        foregroundColor:
                            Colors.white,

                      ),

                      onPressed: () {

                        ScaffoldMessenger.of(
                                context)
                            .showSnackBar(

                          const SnackBar(

                            content: Text(

                              "Edit Inquiry will be implemented next.",

                            ),

                          ),

                        );

                      },

                      icon: const Icon(
                        Icons.edit,
                      ),

                      label: const Text(
                        "Edit Inquiry",
                      ),

                    ),

                  ),

                ),

                const SizedBox(width: 15),

                Expanded(

                  child: SizedBox(

                    height: 52,

                    child: ElevatedButton.icon(

                      style:
                          ElevatedButton.styleFrom(

                        backgroundColor:
                            Colors.green,

                        foregroundColor:
                            Colors.white,

                      ),

                      onPressed: () {

                        ScaffoldMessenger.of(
                                context)
                            .showSnackBar(

                          const SnackBar(

                            content: Text(

                              "Complete Inquiry will be implemented next.",

                            ),

                          ),

                        );

                      },

                      icon: const Icon(
                        Icons.check_circle,

                      ),

                      label: const Text(
                        "Complete",
                      ),

                    ),

                  ),

                ),

              ],

            ),

            const SizedBox(height: 20),
                      ],

        ),

      ),

    );

  }

}