import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/dashboard_card.dart';
import '../../widgets/top_header.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int selectedMenu = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [

          /// LEFT SIDEBAR
          AppSidebar(
            selectedIndex: selectedMenu,
            onItemSelected: (index) {
              setState(() {
                selectedMenu = index;
              });
            },
          ),

          /// RIGHT SIDE
          Expanded(
            child: Column(
              children: [

                const TopHeader(
                  pageTitle: "Dashboard",
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(30),
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

                        const SizedBox(height: 6),

                        const Text(
                          "Operations Overview",
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 35),

                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: 2.1,
                          children: [

                            DashboardCard(
                              title: "Present Today",
                              value: "18",
                              icon: Icons.people,
                              color: Colors.green,
                              onTap: () {},
                            ),

                            DashboardCard(
                              title: "Pending Inquiries",
                              value: "14",
                              icon: Icons.description,
                              color: Colors.orange,
                              onTap: () {},
                            ),

                            DashboardCard(
                              title: "Overdue Inquiries",
                              value: "3",
                              icon: Icons.warning_amber,
                              color: Colors.red,
                              onTap: () {},
                            ),

                            DashboardCard(
                              title: "Cash Sales Today",
                              value: "12",
                              icon: Icons.point_of_sale,
                              color: Colors.blue,
                              onTap: () {},
                            ),
                          ],
                        ),

                        const SizedBox(height: 40),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [

                              const Text(
                                "Today's Alerts",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 25),

                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor:
                                      Color(0xFFFFF3E0),
                                  child: Icon(
                                    Icons.warning,
                                    color: Colors.orange,
                                  ),
                                ),
                                title: const Text(
                                  "3 Customer Inquiries are overdue.",
                                ),
                                subtitle: const Text(
                                  "Please review immediately.",
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () {},
                                  child: const Text("View"),
                                ),
                              ),

                              const Divider(),

                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor:
                                      Color(0xFFE3F2FD),
                                  child: Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                ),
                                title: const Text(
                                  "2 edit requests are awaiting approval.",
                                ),
                                subtitle: const Text(
                                  "Purchase Inquiry edits.",
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}