import 'package:flutter/material.dart';

import '../../utils/inquiry_number_generator.dart';
import '../../theme/app_colors.dart';
import '../../models/inquiry.dart';
import '../../services/inquiry_service.dart';

import 'widgets/inquiry_table.dart';

class InquiryFormScreen extends StatefulWidget {
  const InquiryFormScreen({super.key});

  @override
  State<InquiryFormScreen> createState() =>
      _InquiryFormScreenState();
}

class _InquiryFormScreenState
    extends State<InquiryFormScreen> {

final customerController = TextEditingController();
final addressController = TextEditingController();
final coordinatorController = TextEditingController();
final dueDateController = TextEditingController();
final remarksController = TextEditingController();
final inquiryNumberController = TextEditingController();

double grandTotal = 0;

 @override
void initState() {
  super.initState();

  const String currentUser = "Ali";

  coordinatorController.text = currentUser;

  inquiryNumberController.text =
      InquiryNumberGenerator.generate();
}

  @override
void dispose() {

  customerController.dispose();

  addressController.dispose();

  coordinatorController.dispose();

  dueDateController.dispose();

  remarksController.dispose();

  inquiryNumberController.dispose();

  super.dispose();

}

  Future<void> pickDate() async {

    final picked = await showDatePicker(

      context: context,

      initialDate: DateTime.now(),

      firstDate: DateTime.now(),

      lastDate: DateTime(2100),

    );

    if (picked != null) {

      dueDateController.text =
          "${picked.day}/${picked.month}/${picked.year}";
    }
  }

Widget buildInputField({
  required String label,
  required TextEditingController controller,
  bool readOnly = false,
  int maxLines = 1,
  Widget? suffixIcon,
}) {
  return Column(
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

      TextField(
        controller: controller,
        readOnly: readOnly,
        maxLines: maxLines,
        textCapitalization:
            TextCapitalization.words,
        style: const TextStyle(
          fontSize: 15,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          suffixIcon: suffixIcon,
          contentPadding:
              const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(10),
          ),
        ),
      ),

    ],
  );
}

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
          const Color(0xffF4F6F9),

      appBar: AppBar(

        backgroundColor: AppColors.primary,

        foregroundColor: Colors.white,

        title: const Text(
          "Customer Inquiry",
        ),

      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(25),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            Container(

padding: const EdgeInsets.fromLTRB(
  18,
  16,
  18,
  18,
),

              decoration: BoxDecoration(

                color: Colors.white,

                borderRadius:
                    BorderRadius.circular(18),

                boxShadow: const [

                  BoxShadow(

                    color: Colors.black12,

                    blurRadius: 10,

                  ),

                ],

              ),

              child: Column(

children: [

  const Text(
    "Customer Information",
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  ),

  const SizedBox(height: 16),

const SizedBox(height: 16),

Row(
  crossAxisAlignment:
      CrossAxisAlignment.start,
  children: [

    Expanded(
      flex: 3,
      child: buildInputField(
        label: "Customer Name",
        controller: customerController,
      ),
    ),

    const SizedBox(width: 16),

    Expanded(
      flex: 2,
      child: buildInputField(
        label: "Coordinator",
        controller: coordinatorController,
        readOnly: true,
      ),
    ),

    const SizedBox(width: 16),

    Expanded(
      flex: 2,
      child: buildInputField(
        label: "Inquiry No",
        controller: inquiryNumberController,
        readOnly: true,
      ),
    ),

  ],
),

                  const SizedBox(height:16),

Row(
  crossAxisAlignment:
      CrossAxisAlignment.start,
  children: [

    Expanded(
      flex: 5,
      child: buildInputField(
        label: "Customer Address",
        controller: addressController,
      ),
    ),

    const SizedBox(width: 16),

    Expanded(
      flex: 2,
      child: buildInputField(
        label: "Due Date",
        controller: dueDateController,
        readOnly: true,
        suffixIcon: IconButton(
          icon: const Icon(
            Icons.calendar_month_outlined,
          ),
          onPressed: pickDate,
        ),
      ),
    ),

  ],
),

                ],

              ),

            ),

            const SizedBox(height:10),

            const Text(

              "Inquiry Items",

              style: TextStyle(

                fontSize:20,

                fontWeight:
                    FontWeight.w600,

              ),

            ),

            const SizedBox(height:10),

InquiryTable(
  onGrandTotalChanged: (value) {
    setState(() {
      grandTotal = value;
    });
  },
),  

            const SizedBox(height:25),

            Align(

              alignment:
                  Alignment.centerRight,

              child: Container(

                width:350,

                padding:
                    const EdgeInsets.all(20),

                decoration: BoxDecoration(

                  color: Colors.white,

                  borderRadius:
                      BorderRadius.circular(18),

                  boxShadow: const [

                    BoxShadow(

                      color: Colors.black12,

                      blurRadius:10,

                    )

                  ],

                ),

                child: Column(

                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    const Text(

                      "Grand Total",

                      style: TextStyle(

                        fontSize:18,

                        fontWeight:
                            FontWeight.bold,

                      ),

                    ),

                    const SizedBox(height:10),

                    Text(

                      "PKR ${grandTotal.toStringAsFixed(2)}",

                      style: const TextStyle(

                        fontSize:32,

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
                        const SizedBox(height: 35),

            Row(
              children: [

                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: OutlinedButton.icon(

                      icon: const Icon(Icons.arrow_back),

                      label: const Text(
                        "Cancel",
                      ),

                      onPressed: () {

                        Navigator.pop(context);

                      },

                    ),
                  ),
                ),

                const SizedBox(width: 15),

                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: ElevatedButton.icon(

                      icon: const Icon(Icons.save),

                      label: const Text(
                        "Save Inquiry",
                      ),

                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.primary,
                        foregroundColor:
                            Colors.white,
                      ),

                      onPressed: () {

                        if (customerController.text
                            .trim()
                            .isEmpty) {

                          ScaffoldMessenger.of(context)
                              .showSnackBar(

                            const SnackBar(

                              content: Text(
                                "Customer Name is required",
                              ),

                            ),

                          );

                          return;

                        }

                        InquiryService.instance.addInquiry(

Inquiry(

  id: DateTime.now()
      .millisecondsSinceEpoch
      .toString(),

  customer: customerController.text,

  address: addressController.text,

  coordinator: coordinatorController.text,

  dueDate: dueDateController.text,

  status: "Pending",

  remarks: remarksController.text,

  grandTotal: grandTotal,

  items: [],

),

                        );

                        ScaffoldMessenger.of(context)
                            .showSnackBar(

                          const SnackBar(

                            content: Text(
                              "Inquiry Saved Successfully",
                            ),

                          ),

                        );

                        Navigator.pop(context);

                      },

                    ),
                  ),
                ),

                const SizedBox(width: 15),

                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: ElevatedButton.icon(

                      icon: const Icon(
                        Icons.check_circle,
                      ),

                      label: const Text(
                        "Complete",
                      ),

                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Colors.green,
                        foregroundColor:
                            Colors.white,
                      ),

                      onPressed: () {

                        ScaffoldMessenger.of(context)
                            .showSnackBar(

                          const SnackBar(

                            content: Text(
                              "Complete Inquiry will be implemented next.",
                            ),

                          ),

                        );

                      },

                    ),
                  ),
                ),

              ],
            ),

            const SizedBox(height: 30),

          ],
        ),
      ),
    );
  }
}