import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/data/exercises.dart';
import 'src/app.dart';

const _defaultSupabaseProjectRef = 'vuoxrghazpnmwbulffya';
const _defaultSupabaseUrl = 'https://$_defaultSupabaseProjectRef.supabase.co';
const _defaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ1b3hyZ2hhenBubXdidWxmZnlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU4MTU3MDYsImV4cCI6MjA5MTM5MTcwNn0.4YbQSl6YjT34lbHtR3YdCQbrfd5hCUnw-tHacblYIPc';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrlFromDefine = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKeyFromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');

  final supabaseUrl = supabaseUrlFromDefine.isNotEmpty
      ? supabaseUrlFromDefine
      : _defaultSupabaseUrl;
  final supabaseAnonKey = supabaseAnonKeyFromDefine.isNotEmpty
      ? supabaseAnonKeyFromDefine
      : _defaultSupabaseAnonKey;

  final configured = supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  if (configured) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  await ExerciseDatabase.instance.hydrate();

  runApp(LiftTierFlutterApp(supabaseConfigured: configured));
}
