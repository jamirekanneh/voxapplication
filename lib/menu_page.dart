import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  void _showLanguagePicker(
    BuildContext context,
    LanguageProvider langProvider,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF3E5AB),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select Language",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...langProvider.languages.map(
              (lang) => GestureDetector(
                onTap: () {
                  langProvider.setLanguage(lang);
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: langProvider.selectedLanguage == lang
                        ? Colors.black
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        lang,
                        style: TextStyle(
                          color: langProvider.selectedLanguage == lang
                              ? Colors.white
                              : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (langProvider.selectedLanguage == lang)
                        const Icon(Icons.check, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? trailing,
    VoidCallback? onTap,
    bool isLogout = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: isLogout ? Colors.red : Colors.black87, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isLogout ? Colors.red : Colors.black87,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            if (trailing == null && !isLogout)
              Icon(Icons.chevron_right, color: Colors.grey[500], size: 20),
            if (isLogout)
              Icon(Icons.logout, color: Colors.red.shade300, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 60, bottom: 40),
              decoration: const BoxDecoration(
                color: Color(0xFFD4B96A),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(40),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    "VOX",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFF3E5AB),
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFF3E5AB),
                        width: 2,
                      ),
                    ),
                    child: const CircleAvatar(
                      radius: 38,
                      backgroundColor: Color(0xFFBFA050),
                      child: Icon(
                        Icons.person,
                        size: 40,
                        color: Color(0xFFF3E5AB),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "My Account",
                    style: TextStyle(
                      color: Color(0xFFF3E5AB),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Menu items
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
              child: Column(
                children: [
                  _buildMenuItem(
                    icon: Icons.person_outline,
                    title: "Profile",
                    onTap: () => Navigator.pushNamed(context, '/profile'),
                  ),
                  _buildMenuItem(
                    icon: Icons.language,
                    title: "Language",
                    trailing: langProvider.selectedLanguage,
                    onTap: () => _showLanguagePicker(context, langProvider),
                  ),
                  _buildMenuItem(
                    icon: Icons.bar_chart_outlined,
                    title: "Statistics",
                    onTap: () {},
                  ),
                  _buildMenuItem(
                    icon: Icons.mic_none,
                    title: "Personalized Commands",
                    onTap: () {},
                  ),
                  _buildMenuItem(
                    icon: Icons.info_outline,
                    title: "About Us",
                    onTap: () {},
                  ),
                  _buildMenuItem(
                    icon: Icons.mail_outline,
                    title: "Contact Us",
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  _buildMenuItem(
                    icon: Icons.logout,
                    title: "Logout",
                    isLogout: true,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFFF3E5AB),
                          title: const Text(
                            "Logout",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          content: const Text(
                            "Are you sure you want to logout?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text(
                                "Cancel",
                                style: TextStyle(color: Colors.black),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.pushReplacementNamed(context, '/');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text(
                                "Logout",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomAppBar(
        color: Colors.grey[850],
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(
                Icons.home,
                "Home",
                Colors.grey[400]!,
                onTap: () => Navigator.pushReplacementNamed(context, '/home'),
              ),
              _navItem(
                Icons.note_alt_outlined,
                "Notes",
                Colors.grey[400]!,
                onTap: () => Navigator.pushReplacementNamed(context, '/notes'),
              ),
              const SizedBox(width: 48),
              _navItem(
                Icons.book,
                "Dictionary",
                Colors.grey[400]!,
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/dictionary'),
              ),
              _navItem(Icons.menu, "Menu", Colors.white),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child: const Icon(Icons.file_upload_outlined, color: Colors.white),
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
