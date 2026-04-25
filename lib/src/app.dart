import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/auth/auth_gate.dart';
import 'state/app_settings.dart';
import 'theme/app_theme.dart';
import 'widgets/topological_background.dart';

class LiftTierFlutterApp extends StatefulWidget {
  const LiftTierFlutterApp({required this.supabaseConfigured, super.key});

  final bool supabaseConfigured;

  @override
  State<LiftTierFlutterApp> createState() => _LiftTierFlutterAppState();
}

class _LiftTierFlutterAppState extends State<LiftTierFlutterApp> {
  final _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    unawaited(_settings.hydrate());
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      notifier: _settings,
      child: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) => MaterialApp(
          title: 'LiftTier',
          debugShowCheckedModeBanner: false,
          locale: _settings.isArabic ? const Locale('ar') : const Locale('en'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en'), Locale('ar')],
          theme: AppTheme.dark(
            primary: _settings.primaryColor,
            secondary: _settings.secondaryColor,
          ),
          builder: (context, child) => Directionality(
            textDirection: _settings.textDirection,
            child: child ?? const SizedBox.shrink(),
          ),
          home: widget.supabaseConfigured
              ? const AuthGate()
              : const SupabaseSetupRequiredScreen(),
        ),
      ),
    );
  }
}

class SupabaseSetupRequiredScreen extends StatelessWidget {
  const SupabaseSetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TopologicalBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supabase Configuration Required',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Run with dart defines so the mobile app can connect to your existing database.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    const SelectableText(
                      'flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
