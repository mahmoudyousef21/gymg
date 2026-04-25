import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/topological_background.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;
  bool _loading = true;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _session = client.auth.currentSession;
    _loading = false;

    _authSub = client.auth.onAuthStateChange.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _session = state.session;
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: TopologicalBackground(
          child: Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    if (_session == null) {
      return const LoginScreen();
    }

    return HomeShell(
      key: ValueKey(_session!.user.id),
      userId: _session!.user.id,
      onSignOut: _signOut,
    );
  }
}
