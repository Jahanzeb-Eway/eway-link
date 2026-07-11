import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/top_header.dart';
import '../inquiries/inquiry_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  int selectedMenu = 0;

  final List<String> pageTitles = [
    "Home",
    "Attendance",
    "Customer Inquiries",
    "Cash Sales",
    "Reports",
    "Leave",
    "Settings",
  ];

  Widget getCurrentPage() {

    switch (selectedMenu) {

      case 0:
        return _homePage();

      case 1:
        return const Center(
          child: Text(
            "Attendance Module\nComing Soon",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 2:
        return const InquiryListScreen();

      case 3:
        return const Center(
          child: Text(
            "Cash Sales Module\nComing Soon",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 4:
        return const Center(
          child: Text(
            "Reports Module\nComing Soon",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 5:
        return const Center(
          child: Text(
            "Leave Module\nComing Soon",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 6:
        return const Center(
          child: Text(
            "Settings Module\nComing Soon",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      default:
        return _homePage();
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.background,

      body: Row(
        children: [

          AppSidebar(
            selectedIndex: selectedMenu,
            onItemSelected: (index) {

              setState(() {

                selectedMenu = index;

              });

            },
          ),

          Expanded(
            child: Column(
              children: [

                TopHeader(
                  pageTitle: pageTitles[selectedMenu],
                ),

                Expanded(
                  child: getCurrentPage(),
                ),
                              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _homePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
            "Welcome Back",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            "Operations Dashboard",
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 30),

          Row(
            children: [

              Expanded(
                child: _statCard(
                  "Present Today",
                  "18",
                  Icons.people,
                  Colors.green,
                ),
              ),

              const SizedBox(width: 20),

              Expanded(
                child: _statCard(
                  "Pending Inquiries",
                  "15",
                  Icons.description,
                  Colors.orange,
                ),
              ),

              const SizedBox(width: 20),

              Expanded(
                child: _statCard(
                  "Overdue",
                  "3",
                  Icons.warning_amber,
                  Colors.red,
                ),
              ),

              const SizedBox(width: 20),

              Expanded(
                child: _statCard(
                  "Cash Sales",
                  "12",
                  Icons.point_of_sale,
                  Colors.blue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 35),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                const Text(
                  "Today's Alerts",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3E0),
                    child: Icon(
                      Icons.warning,
                      color: Colors.orange,
                    ),
                  ),
                  title: const Text(
                    "3 Customer Inquiries are overdue.",
                  ),
                  subtitle: const Text(
                    "Immediate follow-up required.",
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedMenu = 2;
                      });
                    },
                    child: const Text("View"),
                  ),
                ),

                const Divider(),

                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    child: Icon(
                      Icons.edit,
                      color: Colors.blue,
                    ),
                  ),
                  title: const Text(
                    "2 Edit Requests Awaiting Approval",
                  ),
                  subtitle: const Text(
                    "Review pending inquiry changes.",
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {},
                    child: const Text("Review"),
                  ),
                ),
                              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            CircleAvatar(
              radius: 24,
              backgroundColor: color.withOpacity(.15),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),

            const SizedBox(height: 25),

            Text(
              value,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}