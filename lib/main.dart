import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'splash_screen.dart';
import 'home_page.dart';
import 'upload_page.dart';
import 'menu_page.dart';
import 'dictionary_page.dart';
import 'notes_page.dart';
import 'language_provider.dart';
import 'tts_service.dart';
import 'temp_library_provider.dart';
import 'temp_notes_provider.dart';
import 'global_stt_wrapper.dart';
import 'custom_commands_provider.dart';
import 'analytics_service.dart';
import 'floating_chat_bot.dart';
import 'notification_service.dart';

final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

// ─────────────────────────────────────────────
//  AUTH WRAPPER - Listens to Firebase auth state
// ─────────────────────────────────────────────
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Listen to auth state changes and load commands for current user
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      final commandsProvider = context.read<CustomCommandsProvider>();
      if (user != null) {
        commandsProvider.loadCommandsForUser(user.uid);
      } else {
        // For anonymous users, use a default UID or handle differently
        commandsProvider.loadCommandsForUser('anonymous');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const TheVoxApp();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: 'assets/project.env');

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Force enable Offline Persistence for the entire Database
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Load saved analytics data and record this app launch
  await AnalyticsService.instance.load();
  await AnalyticsService.instance.recordAppOpen();

  // Initialize notifications service
  await NotificationService.init();

  // Auto-sync analytics to Firebase if needed (daily for authenticated users)
  AnalyticsService.instance.autoSyncIfNeeded();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => TtsService()),
        ChangeNotifierProvider(create: (_) => TempLibraryProvider()),
        ChangeNotifierProvider(create: (_) => TempNotesProvider()),
        ChangeNotifierProvider(create: (_) => CustomCommandsProvider()),
      ],
      child: const AuthWrapper(),
    ),
  );
}

class TheVoxApp extends StatefulWidget {
  const TheVoxApp({super.key});

  @override
  State<TheVoxApp> createState() => _TheVoxAppState();
}

class _TheVoxAppState extends State<TheVoxApp> {
  @override
  void initState() {
    super.initState();
    _handleIncomingLinks();
  }

  Future<void> _handleIncomingLinks() async {
    final appLinks = AppLinks();

    final Uri? initialLink = await appLinks.getInitialLink();
    if (initialLink != null) {
      await _completeMagicLinkSignIn(initialLink.toString());
    }

    appLinks.uriLinkStream.listen((Uri link) async {
      await _completeMagicLinkSignIn(link.toString());
    });
  }

  Future<void> _completeMagicLinkSignIn(String link) async {
    if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) return;

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('pendingEmailLink');

    if (email == null) return;

    try {
      await FirebaseAuth.instance.signInWithEmailLink(
        email: email,
        emailLink: link,
      );
      await prefs.remove('pendingEmailLink');
    } catch (e) {
      debugPrint("Magic link sign-in error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: globalNavigatorKey,
      // Wrap the SplashScreen with the GlobalSttWrapper
      home: const GlobalSttWrapper(child: SplashScreen()),
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
