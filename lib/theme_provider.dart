import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────
//  THEME PROVIDER  –  persists & notifies theme mode changes
// ─────────────────────────────────────────────────────────────
class ThemeProvider extends ChangeNotifier {
  static const String _key = 'vox_theme_mode';

  ThemeMode _themeMode = ThemeMode.dark; // dark is the default Vox look

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key) ?? 'dark';
    _themeMode = saved == 'light' ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.light ? 'light' : 'dark');
  }

  Future<void> toggle() async =>
      setMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

// ─────────────────────────────────────────────────────────────
//  VOX COLORS  –  context-aware design tokens
//  Usage:  VoxColors.bg(context)   VoxColors.primary(context)
// ─────────────────────────────────────────────────────────────
class VoxColors {
  VoxColors._();

  // ── Raw palette ──────────────────────────────────────────
  static const Color _darkBg          = Color(0xFF0A0E1A);
  static const Color _darkSurface     = Color(0xFF141A29);
  static const Color _darkSurface2    = Color(0xFF1A1F33);
  static const Color _darkSurface3    = Color(0xFF0F1629);
  static const Color _neonBlue        = Color(0xFF4B9EFF);
  static const Color _brightBlue      = Color(0xFF1A6FFF);

  static const Color _lightBg         = Color(0xFFEBF2FF);
  static const Color _lightSurface    = Color(0xFFFFFFFF);
  static const Color _lightSurface2   = Color(0xFFF0F5FF);
  static const Color _lightSurface3   = Color(0xFFE0EAFF);
  static const Color _lightOnBg       = Color(0xFF0A0E1A);

  // ── Context-aware tokens ─────────────────────────────────
  static bool _isDark(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark;

  static Color bg(BuildContext ctx) =>
      _isDark(ctx) ? _darkBg : _lightBg;

  static Color surface(BuildContext ctx) =>
      _isDark(ctx) ? _darkSurface : _lightSurface;

  static Color surface2(BuildContext ctx) =>
      _isDark(ctx) ? _darkSurface2 : _lightSurface2;

  static Color surface3(BuildContext ctx) =>
      _isDark(ctx) ? _darkSurface3 : _lightSurface3;

  static Color primary(BuildContext ctx) =>
      _isDark(ctx) ? _neonBlue : _brightBlue;

  static Color onBg(BuildContext ctx) =>
      _isDark(ctx) ? Colors.white : _lightOnBg;

  static Color onSurface(BuildContext ctx) =>
      _isDark(ctx) ? Colors.white : _lightOnBg;

  static Color textSecondary(BuildContext ctx) =>
      _isDark(ctx)
          ? Colors.white.withValues(alpha: 0.5)
          : _lightOnBg.withValues(alpha: 0.55);

  static Color textHint(BuildContext ctx) =>
      _isDark(ctx)
          ? Colors.white.withValues(alpha: 0.25)
          : _lightOnBg.withValues(alpha: 0.3);

  static Color border(BuildContext ctx) =>
      _isDark(ctx)
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.09);

  static Color borderStrong(BuildContext ctx) =>
      _isDark(ctx)
          ? Colors.white.withValues(alpha: 0.15)
          : Colors.black.withValues(alpha: 0.15);

  static Color cardFill(BuildContext ctx) =>
      _isDark(ctx)
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.white.withValues(alpha: 0.9);

  static Color onPrimary(BuildContext ctx) => Colors.white;

  /// Use for brand highlights or special states
  static Color accent(BuildContext ctx) =>
      _isDark(ctx) ? const Color(0xFF25D366) : const Color(0xFF25D366);

  static Color iconOnBg(BuildContext ctx) => primary(ctx);

  /// Use for danger actions (logout, delete)
  static const Color danger = Color(0xFFFF5252);
}

// ─────────────────────────────────────────────────────────────
//  APP THEME  –  full ThemeData for light and dark
// ─────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  // ── DARK (existing Vox Navy + Neon Blue look) ─────────────
  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0A0E1A),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF4B9EFF),
      secondary: Color(0xFF4B9EFF),
      surface: Color(0xFF141A29),
      onPrimary: Colors.white,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0A0E1A),
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      color: Color(0xFF141A29),
      elevation: 0,
    ),
    cardColor: const Color(0xFF141A29),
    dialogBackgroundColor: const Color(0xFF141A29),
    dividerColor: Colors.white12,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF4B9EFF)
              : Colors.white38),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF4B9EFF).withValues(alpha: 0.35)
              : Colors.white12),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Colors.white),
      bodySmall: TextStyle(color: Colors.white70),
    ),
  );

  // ── LIGHT (bright blue-predominant) ──────────────────────
  static final ThemeData light = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFEBF2FF),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF1A6FFF),
      secondary: Color(0xFF4B9EFF),
      surface: Colors.white,
      onPrimary: Colors.white,
      onSurface: Color(0xFF0A0E1A),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF0A0E1A),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      color: Colors.white,
      elevation: 0,
    ),
    cardColor: Colors.white,
    dialogBackgroundColor: Colors.white,
    dividerColor: Colors.black12,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF1A6FFF)
              : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF1A6FFF).withValues(alpha: 0.4)
              : Colors.black12),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Color(0xFF0A0E1A)),
      bodySmall: TextStyle(color: Color(0xFF3A4A6A)),
    ),
  );
}
