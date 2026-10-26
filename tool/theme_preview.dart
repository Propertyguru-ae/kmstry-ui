// Local-only native visual QA. Never use this target for a store build.
// flutter run -t tool/theme_preview.dart --dart-define=THEME_CAPTURE=true
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/core/theme/appearance_system_ui.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/startup_gate_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/startup_brand.dart';
import '../test/support/theme_screens.dart';

class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (_, _, _) async {
          throw StateError('Theme preview cannot connect to a server');
        };
}

Future<void> main() async {
  if (kReleaseMode) throw StateError('Theme preview is debug-only');
  WidgetsFlutterBinding.ensureInitialized();
  // Optional local-only pause before the first Flutter frame to inspect the
  // actual OS launch screen, not a Flutter recreation of it.
  const nativeSplashHold = int.fromEnvironment('NATIVE_SPLASH_HOLD_MS');
  if (nativeSplashHold > 0) {
    await Future<void>.delayed(Duration(milliseconds: nativeSplashHold));
  }
  // In-memory preview only: show first-launch UI without modifying device prefs.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = _Offline();
  final theme = ThemeProvider(
    readPreference: () async => null,
    writePreference: (_) async {},
  );
  await theme.ready;
  await StartupBrand.warmUp();
  runApp(
    ChangeNotifierProvider.value(
      value: theme,
      child: Consumer<ThemeProvider>(
        builder: (_, appearance, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          builder: (_, child) => AppearanceSystemUi(child: child!),
          themeMode: appearance.themeMode,
          home: const bool.fromEnvironment('STARTUP_ONLY')
              ? const StartupGatePage()
              : const _Preview(),
        ),
      ),
    ),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> with WidgetsBindingObserver {
  final _captureKey = GlobalKey();
  late final _screens = <String, Widget Function()>{
    'startup': () => const StartupGatePage(),
    ...themePreviewScreens(),
  };
  String? _selected;
  bool _capturing = false;
  int _errors = 0;
  FlutterExceptionHandler? _previousErrorHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      _errors++;
      _previousErrorHandler?.call(details);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _logSystemTheme();
      if (const bool.fromEnvironment('THEME_CAPTURE')) await _captureAll();
    });
  }

  @override
  void didChangePlatformBrightness() {
    // ThemeData animates for 200 ms; inspect the settled native appearance.
    Future<void>.delayed(const Duration(milliseconds: 500), _logSystemTheme);
  }

  void _logSystemTheme() {
    if (!mounted) return;
    debugPrint(
      'THEME_NATIVE mode=${context.read<ThemeProvider>().themeMode.name} '
      'platform=${WidgetsBinding.instance.platformDispatcher.platformBrightness.name} '
      'effective=${Theme.of(context).brightness.name}',
    );
  }

  Future<void> _captureAll() async {
    setState(() => _capturing = true);
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/theme-preview',
    );
    await dir.create(recursive: true);
    if (!mounted) return;
    final provider = context.read<ThemeProvider>();
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await provider.setThemeMode(mode);
      for (final name in _screens.keys) {
        if (!mounted) return;
        setState(() => _selected = name);
        await Future<void>.delayed(
          Duration(milliseconds: name == 'startup' ? 1400 : 700),
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final boundary =
            _captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(
          '${dir.path}/${mode.name}-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        debugPrint('THEME_CAPTURE ${mode.name} $name');
      }
    }
    await provider.setThemeMode(ThemeMode.system);
    if (!mounted) return;
    setState(() {
      _selected = null;
      _capturing = false;
    });
    debugPrint(
      'THEME_CAPTURE_DONE count=${_screens.length * 2} errors=$_errors path=${dir.path}',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterError.onError = _previousErrorHandler;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();
    if (_selected != null) {
      return RepaintBoundary(
        key: _captureKey,
        child: AbsorbPointer(
          absorbing: _capturing,
          child: KeyedSubtree(
            key: ValueKey(_selected),
            child: _screens[_selected]!(),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Local theme QA · offline')),
      body: ListView(
        children: [
          ListTile(
            title: Text('Auto / system: ${Theme.of(context).brightness.name}'),
          ),
          for (final mode in ThemeMode.values)
            RadioListTile<ThemeMode>(
              title: Text(mode == ThemeMode.system ? 'Auto' : mode.name),
              value: mode,
              // Kept compatible with the project's installed Flutter SDK.
              // ignore: deprecated_member_use
              groupValue: provider.themeMode,
              // ignore: deprecated_member_use
              onChanged: (value) async {
                await provider.setThemeMode(value!);
                _logSystemTheme();
              },
            ),
          for (final name in _screens.keys)
            ListTile(
              title: Text(name),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => _screens[name]!())),
            ),
        ],
      ),
    );
  }
}
