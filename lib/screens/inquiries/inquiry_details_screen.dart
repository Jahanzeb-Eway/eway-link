import 'package:flutter/material.dart';

class InquiryDetailsScreen extends StatelessWidget {
  const InquiryDetailsScreen({super.key});

  Widget infoTile(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [

          SizedBox(
            width: 150,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Expanded(
            child: Text(value),
          ),

        ],
      ),
    );
  }

  Widget itemCard(
      String item,
      String vendor,
      String qty,
      String rate,
      String total,
      ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(

        title: Text(
          item,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [

            Text("Vendor : $vendor"),

            Text("Qty : $qty"),

            Text("Rate : $rate"),

          ],
        ),

        trailing: Text(
          total,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xffF4F6F9),

      appBar: AppBar(
        title: const Text("Inquiry Details"),
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(25),

        child: Column(

          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [

            Card(

              child: Padding(

                padding: const EdgeInsets.all(20),

                child: Column(

                  children: [

                    infoTile(
                        "Inquiry No",
                        "INQ-260711-001"),

                    infoTile(
                        "Customer",
                        "ABC Construction"),

                    infoTile(
                        "Address",
                        "Lahore"),

                    infoTile(
                        "Due Date",
                        "15-Jul-2026"),

                    infoTile(
                        "Status",
                        "Pending"),

                    infoTile(
                        "Coordinator",
                        "Ali"),

                  ],

                ),

              ),

            ),

            const SizedBox(height:25),

            const Text(

              "Inquiry Items",

              style: TextStyle(
                fontSize:22,
                fontWeight: FontWeight.bold,
              ),

            ),

            const SizedBox(height:15),

            itemCard(
              "Steel Pipe",
              "Mughal Steel",
              "100",
              "250",
              "25000",
            ),

            itemCard(
              "Steel Angle",
              "Ittefaq",
              "50",
              "400",
              "20000",
            ),

            itemCard(
              "Cement",
              "Lucky Cement",
              "250",
              "1450",
              "362500",
            ),
                        const SizedBox(height: 25),

            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.all(20),
                width: 320,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: const [

                    Text(
                      "Grand Total",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 10),

                    Text(
                      "PKR 407,500",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),

                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              "Remarks",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "Customer requires urgent quotation. "
                  "Follow up before due date.",
                ),
              ),
            ),

            const SizedBox(height: 25),

            Row(
              children: [

                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text("Edit"),
                    onPressed: () {},
                  ),
                ),

                const SizedBox(width: 15),

                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text("Complete"),
                    onPressed: () {},
                  ),
                ),

                const SizedBox(width: 15),

                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text("Print"),
                    onPressed: () {},
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