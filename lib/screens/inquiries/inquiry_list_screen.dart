import 'package:flutter/material.dart';

import '../../models/inquiry.dart';
import '../../services/inquiry_service.dart';

import 'inquiry_form_screen.dart';
import 'inquiry_details_screen.dart';

class InquiryListScreen extends StatefulWidget {
  const InquiryListScreen({super.key});

  @override
  State<InquiryListScreen> createState() =>
      _InquiryListScreenState();
}

class _InquiryListScreenState
    extends State<InquiryListScreen> {

  final searchController =
      TextEditingController();

  @override
  void dispose() {

    searchController.dispose();

    super.dispose();

  }

  List<Inquiry> get inquiries {

    return InquiryService.instance
        .getAllInquiries();

  }

  List<Inquiry> get pending {

    return inquiries
        .where(
          (e) =>
              e.status == "Pending",
        )
        .toList();

  }

  List<Inquiry> get completed {

    return inquiries
        .where(
          (e) =>
              e.status == "Completed",
        )
        .toList();

  }

  List<Inquiry> get overdue {

    return inquiries
        .where(
          (e) =>
              e.status == "Overdue",
        )
        .toList();

  }

  Widget statCard({

    required String title,

    required String value,

    required Color color,

    required IconData icon,

  }) {

    return Expanded(

      child: Container(

        height: 105,

        margin:
            const EdgeInsets.symmetric(
          horizontal: 6,
        ),

        decoration: BoxDecoration(

          color: Colors.white,

          borderRadius:
              BorderRadius.circular(15),

          boxShadow: const [

            BoxShadow(

              color: Colors.black12,

              blurRadius: 8,

            ),

          ],

        ),

        child: Column(

          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [

            CircleAvatar(

              backgroundColor:
                  color.withOpacity(.15),

              child: Icon(

                icon,

                color: color,

              ),

            ),

            const SizedBox(height: 10),

            Text(

              value,

              style: const TextStyle(

                fontSize: 24,

                fontWeight:
                    FontWeight.bold,

              ),

            ),

            Text(title),

          ],

        ),

      ),

    );

  }

    Widget inquiryCard(
    Inquiry inquiry,
  ) {

    Color statusColor;

    switch (inquiry.status) {

      case "Completed":
        statusColor = Colors.green;
        break;

      case "Overdue":
        statusColor = Colors.red;
        break;

      default:
        statusColor = Colors.orange;

    }

    return Card(

      elevation: 2,

      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),

      child: ListTile(

        leading: const CircleAvatar(
          child: Icon(
            Icons.description,
          ),
        ),

        title: Text(

          inquiry.id,

          style: const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),

        ),

        subtitle: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            const SizedBox(height: 4),

            Text(
              inquiry.customer,
            ),

            Text(

              "Coordinator : ${inquiry.coordinator}",

              style: const TextStyle(
                fontSize: 12,
              ),

            ),

          ],

        ),

        trailing: SizedBox(

          width: 320,

          child: Row(

            mainAxisAlignment:
                MainAxisAlignment.end,

            children: [

              Column(

                mainAxisAlignment:
                    MainAxisAlignment.center,

                children: [

                  const Text(

                    "Due",

                    style: TextStyle(
                      fontSize: 11,
                    ),

                  ),

                  Text(

                    inquiry.dueDate,

                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),

                  ),

                ],

              ),

              const SizedBox(width: 12),

              Container(

                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),

                decoration: BoxDecoration(

                  color:
                      statusColor.withOpacity(.15),

                  borderRadius:
                      BorderRadius.circular(20),

                ),

                child: Text(

                  inquiry.status,

                  style: TextStyle(

                    color: statusColor,

                    fontWeight:
                        FontWeight.bold,

                  ),

                ),

              ),

              IconButton(

                icon: const Icon(
                  Icons.visibility,
                ),

                onPressed: () {

                  Navigator.push(

                    context,

                    MaterialPageRoute(

                      builder: (_) =>
                          InquiryDetailsScreen(
                        inquiry: inquiry,
                      ),

                    ),

                  );

                },

              ),

              IconButton(

                icon: const Icon(
                  Icons.edit,
                ),

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

      backgroundColor:
          const Color(0xffF4F6F9),

      floatingActionButton:
          FloatingActionButton.extended(

        icon: const Icon(Icons.add),

        label: const Text(
          "New Inquiry",
        ),

        onPressed: () async {

          await Navigator.push(

            context,

            MaterialPageRoute(

              builder: (_) =>
                  const InquiryFormScreen(),

            ),

          );

          setState(() {});

        },

      ),

      body: Padding(

        padding:
            const EdgeInsets.all(24),

        child: Column(

          children: [

            Row(

              children: [

                const Text(

                  "Customer Inquiries",

                  style: TextStyle(

                    fontSize: 28,

                    fontWeight:
                        FontWeight.bold,

                  ),

                ),

                const Spacer(),

                SizedBox(

                  width: 350,

                  child: TextField(

                    controller:
                        searchController,

                    onChanged: (_) {

                      setState(() {});

                    },

                    decoration:
                        InputDecoration(

                      hintText:
                          "Search Inquiry...",

                      prefixIcon:
                          const Icon(
                        Icons.search,
                      ),

                      border:
                          OutlineInputBorder(

                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),

                      ),

                    ),

                  ),

                ),

              ],

            ),

            const SizedBox(height: 24),

            Row(

              children: [

                statCard(

                  title: "Pending",

                  value:
                      pending.length.toString(),

                  color: Colors.orange,

                  icon:
                      Icons.pending_actions,

                ),

                statCard(

                  title: "Completed",

                  value: completed.length
                      .toString(),

                  color: Colors.green,

                  icon:
                      Icons.check_circle,

                ),

                statCard(

                  title: "Overdue",

                  value:
                      overdue.length.toString(),

                  color: Colors.red,

                  icon: Icons.warning,

                ),

                statCard(

                  title: "Total",

                  value:
                      inquiries.length.toString(),

                  color: Colors.blue,

                  icon:
                      Icons.description,

                ),

              ],

            ),

            const SizedBox(height: 24),

            Expanded(

              child: inquiries.isEmpty

                  ? Center(

                      child: Column(

                        mainAxisAlignment:
                            MainAxisAlignment.center,

                        children: [

                          Icon(

                            Icons.description_outlined,

                            size: 70,

                            color:
                                Colors.grey.shade400,

                          ),

                          const SizedBox(
                              height: 16),

                          const Text(

                            "No inquiries found",

                            style: TextStyle(

                              fontSize: 20,

                              fontWeight:
                                  FontWeight.w600,

                            ),

                          ),

                          const SizedBox(
                              height: 8),

                          const Text(

                            "Click 'New Inquiry' to create your first inquiry.",

                            style: TextStyle(

                              color:
                                  Colors.grey,

                            ),

                          ),

                        ],

                      ),

                    )

                  : ListView.builder(

                      itemCount:
                          inquiries.length,

                      itemBuilder:
                          (context, index) {

                        final inquiry =
                            inquiries[index];

                        if (searchController
                            .text
                            .isNotEmpty) {

                          final keyword =
                              searchController
                                  .text
                                  .toLowerCase();

                          if (!inquiry.customer
                                  .toLowerCase()
                                  .contains(keyword) &&
                              !inquiry.id
                                  .toLowerCase()
                                  .contains(keyword)) {

                            return const SizedBox();

                          }

                        }

                        return inquiryCard(
                          inquiry,
                        );

                      },

                    ),

            ),

          ],

        ),

      ),

    );

  }
  }