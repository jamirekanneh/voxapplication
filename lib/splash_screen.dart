import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_profile.dart';
import 'home_page.dart';

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
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    await Future.delayed(const Duration(milliseconds: 3500));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool hasProfile = prefs.getBool('hasProfile') ?? false;

    if (!mounted) return;

    final Widget nextScreen = hasProfile
        ? const VoxHomePage()
        : const UserProfilePage();

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => nextScreen,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
            // ── LAYER 1: Full-screen watermarked logo ──────────────────────
            // Positioned.fill pins all 4 edges to the Stack's bounds,
            // guaranteeing full-screen coverage on Flutter Web and mobile.
            Positioned.fill(
              child: Opacity(
                opacity: 0.07,
                child: Image.asset(
                  'assets/images/vox_logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),

            // ── LAYER 2: Radial vignette ──────────────────────────────────
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0A0E1A).withOpacity(0.55),
                    const Color(0xFF0A0E1A).withOpacity(0.85),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),

            // ── LAYER 3: Subtle blue centre-glow ─────────────────────────
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    const Color(0xFF4B9EFF).withOpacity(0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),

            // ── LAYER 4: Foreground content ───────────────────────────────
            FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Centred logo mark with glow
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF4B9EFF,
                            ).withOpacity(0.3),
                            blurRadius: 60,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: const Color(
                              0xFF4B9EFF,
                            ).withOpacity(0.1),
                            blurRadius: 100,
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/vox_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.auto_awesome_rounded,
                              color: Color(0xFF4B9EFF),
                              size: 90,
                            ),
                      ),
                    ),
                    const SizedBox(height: 54),

                    // App name
                    const Text(
                      "VOX",
                      style: TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 18.0,
                        height: 1,
                        shadows: [
                          Shadow(
                            color: Color(0xFF4B9EFF),
                            blurRadius: 20,
                            offset: Offset(0, 0),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Tagline pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4B9EFF).withOpacity(0.05),
                        border: Border.all(
                          color: const Color(0xFF4B9EFF).withOpacity(0.4),
                          width: 1.5,
                        ),
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

            // ── LAYER 5: Loading bar at bottom ────────────────────────────
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
                        backgroundColor: Colors.white.withOpacity(0.03),
                        color: const Color(0xFF4B9EFF),
                        minHeight: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "INITIALIZING SYSTEM",
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white.withOpacity(0.3),
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
