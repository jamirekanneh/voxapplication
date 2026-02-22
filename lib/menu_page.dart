import 'package:flutter/material.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String selectedLanguage = "French";
  final List<String> languages = [
    "Spanish",
    "Chinese",
    "Turkish",
    "Arabic",
    "French",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF2B3), // Image 2 Yellow
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 50, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            const Text(
              "Profile",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            const Text(
              "Select Language",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: languages.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(languages[index]),
                    trailing: selectedLanguage == languages[index]
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () =>
                        setState(() => selectedLanguage = languages[index]),
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
