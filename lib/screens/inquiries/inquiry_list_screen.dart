import 'package:flutter/material.dart';

import 'inquiry_form_screen.dart';
import 'inquiry_details_screen.dart';

class InquiryListScreen extends StatefulWidget {
  const InquiryListScreen({super.key});

  @override
  State<InquiryListScreen> createState() => _InquiryListScreenState();
}

class _InquiryListScreenState extends State<InquiryListScreen> {
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Widget buildStatCard(
      String title,
      String value,
      Color color,
      IconData icon,
      ) {
    return Expanded(
      child: Container(
        height: 105,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            CircleAvatar(
              backgroundColor: color.withOpacity(.15),
              child: Icon(icon, color: color),
            ),

            const SizedBox(height: 10),

            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            Text(title),
          ],
        ),
      ),
    );
  }

  Widget inquiryRow(
      BuildContext context,
      String inquiryNo,
      String customer,
      String dueDate,
      String status,
      Color statusColor,
      String coordinator,
      ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.description),
        ),

        title: Text(
          inquiryNo,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const SizedBox(height: 4),

            Text(customer),

            Text(
              "Coordinator : $coordinator",
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),

        trailing: SizedBox(
          width: 300,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [

              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  const Text(
                    "Due",
                    style: TextStyle(fontSize: 11),
                  ),

                  Text(
                    dueDate,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 12),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              IconButton(
                icon: const Icon(Icons.visibility),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const InquiryDetailsScreen(),
                    ),
                  );
                },
              ),

              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const InquiryFormScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F6F9),

      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text("New Inquiry"),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
              const InquiryFormScreen(),
            ),
          );
        },
      ),

      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [

            Row(
              children: [

                const Text(
                  "Customer Inquiries",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const Spacer(),

                SizedBox(
                  width: 350,
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            Row(
              children: [

                buildStatCard(
                  "Pending",
                  "15",
                  Colors.orange,
                  Icons.pending_actions,
                ),

                buildStatCard(
                  "Completed",
                  "42",
                  Colors.green,
                  Icons.check_circle,
                ),

                buildStatCard(
                  "Overdue",
                  "3",
                  Colors.red,
                  Icons.warning,
                ),

                buildStatCard(
                  "Total",
                  "60",
                  Colors.blue,
                  Icons.description,
                ),
              ],
            ),

            const SizedBox(height: 30),

            Expanded(
              child: ListView(
                children: [

                  inquiryRow(
                    context,
                    "INQ-260711-001",
                    "ABC Construction",
                    "15-Jul-2026",
                    "Pending",
                    Colors.orange,
                    "Ali",
                  ),

                  inquiryRow(
                    context,
                    "INQ-260711-002",
                    "Packages Ltd",
                    "14-Jul-2026",
                    "Completed",
                    Colors.green,
                    "Usman",
                  ),

                  inquiryRow(
                    context,
                    "INQ-260711-003",
                    "Nishat Mills",
                    "12-Jul-2026",
                    "Overdue",
                    Colors.red,
                    "Ali",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}