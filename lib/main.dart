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
import 'theme_provider.dart';
import 'analytics_service.dart';
import 'notification_service.dart';
import 'saved_assessments_page.dart';
import 'profile_page.dart';
import 'custom_commands_page.dart';
import 'about_us_page.dart';
import 'statistics_page.dart';
import 'contact_us_page.dart';
import 'ask_questions_page.dart';
import 'recommendations_page.dart';
import 'recycle_bin_page.dart';
import 'history_page.dart';

final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

// ─────────────────────────────────────────────
//  AUTH WRAPPER - Listens to Firebase auth state
// ─────────────────────────────────────────────
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show splash/loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SplashScreen(),
          );
        }

        final user = snapshot.data;
        
        // Update CustomCommandsProvider when auth state changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            final commandsProvider = context.read<CustomCommandsProvider>();
            commandsProvider.loadCommandsForUser(user?.uid ?? 'anonymous');
          }
        });

        // TheVoxApp now only contains the theme/routes/etc.
        // It doesn't need to handle its own root navigation as much.
        return const TheVoxApp();
      },
    );
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
  await NotificationService.instance.init();
  await NotificationService.instance.scheduleDailyReminder(20, 0); // 8:00 PM

  // Auto-sync analytics to Firebase if needed (daily for authenticated users)
  AnalyticsService.instance.autoSyncIfNeeded();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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

      // Give the navigator a moment to be ready, then navigate to home.
      // This is critical: without this, sign-in completes silently while
      // the splash screen has already navigated to the sign-in page.
      await Future.delayed(const Duration(milliseconds: 300));
      globalNavigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
      );
    } catch (e) {
      debugPrint("Magic link sign-in error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: globalNavigatorKey,
      themeMode: themeProvider.themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Wrap the entire app routing navigator with GlobalSttWrapper
      builder: (context, child) => GlobalSttWrapper(child: child!),
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const VoxHomePage(),
        '/upload': (context) => const UploadPage(),
        '/menu': (context) => const MenuPage(),
        '/dictionary': (context) => const DictionaryPage(),
        '/notes': (context) => const NotesPage(),
        '/saved_assessments': (context) => const SavedAssessmentsPage(),
        '/profile': (context) => const ProfilePage(),
        '/custom_commands': (context) => const CustomCommandsPage(),
        '/about': (context) => const AboutUsPage(),
        '/statistics': (context) => const StatisticsPage(),
        '/contact': (context) => const ContactUsPage(),
        '/faqs': (context) => const AskQuestionsPage(),
        '/recommendations': (context) => const RecommendationsPage(),
        '/recycle_bin': (context) => const RecycleBinPage(),
        '/history': (context) => HistoryScreen(),
      },
    );
  }
}
