import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'user_profile.dart';
import 'home_page.dart';
import 'services/app_session.dart';
import 'services/auth_session.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.bounceInOut));
    _controller.forward();
    _checkDeviceHistory();
  }

  Future<void> _checkDeviceHistory() async {
    Widget nextScreen = const UserProfilePage(isEditingMode: false);
    String? welcomeMessage;

    try {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;

      final destination = await AppSession.resolveLaunchDestination().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('Splash: launch routing timed out, using local prefs.');
          return LaunchDestination.profile;
        },
      );

      final authUser = FirebaseAuth.instance.currentUser;

      if (destination == LaunchDestination.home) {
        nextScreen = const VoxHomePage();
        unawaited(AppSession.markSetupComplete(userId: authUser?.uid));
        if (authUser != null && !authUser.isAnonymous) {
          welcomeMessage = 'Welcome back.';
        } else if (await AuthSession.isExplicitGuestMode()) {
          welcomeMessage = 'Continuing as guest.';
        }
      }
    } catch (e, st) {
      debugPrint('Splash routing error: $e\n$st');
      if (await AuthSession.isSignedIn() ||
          await AuthSession.isExplicitGuestMode()) {
        nextScreen = const VoxHomePage();
      }
    } finally {
      FlutterNativeSplash.remove();
    }

    if (!mounted) return;

    if (welcomeMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            welcomeMessage,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF4B9EFF),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.07,
                child: Image.asset(
                  'assets/images/vox_logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0A0E1A).withValues(alpha: 0.55),
                    const Color(0xFF0A0E1A).withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    const Color(0xFF4B9EFF).withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4B9EFF).withValues(alpha: 0.3),
                            blurRadius: 60,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/vox_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF4B9EFF), size: 90),
                      ),
                    ),
                    const SizedBox(height: 54),
                    const Text(
                      "VOX",
                      style: TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 18.0,
                        height: 1,
                        shadows: [
                          Shadow(color: Color(0xFF4B9EFF), blurRadius: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4B9EFF).withValues(alpha: 0.05),
                        border: Border.all(color: const Color(0xFF4B9EFF).withValues(alpha: 0.4), width: 1.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "SOLVING ALL YOUR STUDENT PROBLEMS",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 60,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withValues(alpha: 0.03),
                        color: const Color(0xFF4B9EFF),
                        minHeight: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "INITIALIZING SYSTEM",
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white.withValues(alpha: 0.3),
                        letterSpacing: 3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}