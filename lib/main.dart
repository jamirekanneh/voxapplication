import 'dart:async';
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
import 'saved_docs_page.dart';
import 'profile_page.dart';
import 'custom_commands_page.dart';
import 'about_us_page.dart';
import 'statistics_page.dart';
import 'contact_us_page.dart';
import 'ask_questions_page.dart';
import 'recommendations_page.dart';
import 'recycle_bin_page.dart';
import 'reminders_page.dart';
import 'history_page.dart';
import 'services/mic_route_observer.dart';
import 'services/auth_session.dart';
import 'services/app_session.dart';

final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StreamSubscription<User?> _authSubscription;

  @override
  void initState() {
    super.initState();
    // Listen to auth changes and load custom commands for logged in users.
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        context
            .read<CustomCommandsProvider>()
            .loadCommandsForUser(user.uid);
      }
    });
    _handleIncomingLinks();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
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
      final cred = await FirebaseAuth.instance.signInWithEmailLink(
        email: email,
        emailLink: link,
      );
      await prefs.remove('pendingEmailLink');

      final user = cred.user;
      if (user != null) {
        await AuthSession.markSignedIn(user);
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          if (doc.exists) {
            final name = (doc.data()?['username'] as String?)?.trim();
            if (name != null && name.isNotEmpty) {
              await prefs.setString('userName', name);
            }
          }
        } catch (_) {}
        await AppSession.markSetupComplete(userId: user.uid);
      }

      // Give the navigator a moment to be ready, then navigate to home.
      await Future.delayed(const Duration(milliseconds: 300));
      globalNavigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/home', (route) => false);
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
      navigatorObservers: [MicRouteObserver()],
      themeMode: themeProvider.themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) => GlobalSttWrapper(child: child!),
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const VoxHomePage(),
        '/upload': (context) => const UploadPage(),
        '/menu': (context) => const MenuPage(),
        '/dictionary': (context) => const DictionaryPage(),
        '/notes': (context) => const NotesPage(),
        '/saved_docs': (context) => const SavedDocsPage(),
        '/saved_assessments': (context) => const SavedDocsPage(),
        '/profile': (context) => const ProfilePage(),
        '/custom_commands': (context) => const CustomCommandsPage(),
        '/about': (context) => const AboutUsPage(),
        '/statistics': (context) => const StatisticsPage(),
        '/contact': (context) => const ContactUsPage(),
        '/faqs': (context) => const AskQuestionsPage(),
        '/recommendations': (context) => const RecommendationsPage(),
        '/recycle_bin': (context) => const RecycleBinPage(),
        '/reminders': (context) => const RemindersPage(),
        '/history': (context) => HistoryScreen(),
      },
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: 'assets/project.env');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Show the full Flutter splash (VOX + tagline + INITIALIZING) ASAP.
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
      child: const MyApp(),
    ),
  );
}
