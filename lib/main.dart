import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'splash_screen.dart';
import 'home_page.dart';
import 'upload_page.dart';
import 'menu_page.dart';
import 'dictionary_page.dart';
import 'notes_page.dart';
import 'language_provider.dart';
import 'reader_provider.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  runApp(
    
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => ReaderProvider()),
      ],
      child: const TheVoxApp(),
    ),
  );
}

class TheVoxApp extends StatefulWidget {        // ← changed to StatefulWidget
  const TheVoxApp({super.key});

  @override
  State<TheVoxApp> createState() => _TheVoxAppState();
}

class _TheVoxAppState extends State<TheVoxApp> {

  @override
  void initState() {
    super.initState();
    _handleIncomingLinks();                     // ← starts listening for magic links
  }

  Future<void> _handleIncomingLinks() async {
    final appLinks = AppLinks();

    // Cold start — app was closed when user tapped the link
    final Uri? initialLink = await appLinks.getInitialLink();
    if (initialLink != null) {
      await _completeMagicLinkSignIn(initialLink.toString());
    }

    // Warm start — app was in background when user tapped the link
    appLinks.uriLinkStream.listen((Uri link) async {
      await _completeMagicLinkSignIn(link.toString());
    });
  }

  Future<void> _completeMagicLinkSignIn(String link) async {
    if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) return;

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('pendingEmailLink');

    // No email stored means link arrived on a different device — ignore
    if (email == null) return;

    try {
      await FirebaseAuth.instance.signInWithEmailLink(
        email: email,
        emailLink: link,
      );
      await prefs.remove('pendingEmailLink');
      // authStateChanges() in _AwaitingLinkView picks this up automatically
      // and navigates to /home — no extra code needed here
    } catch (e) {
      debugPrint("Magic link sign-in error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const VoxHomePage(),
        '/upload': (context) => const UploadPage(),
        '/menu': (context) => const MenuPage(),
        '/dictionary': (context) => const DictionaryPage(),
        '/notes': (context) => const NotesPage(),
        
      },
    );
  }
}