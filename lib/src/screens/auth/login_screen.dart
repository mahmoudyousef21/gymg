import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/topological_background.dart';

enum _AuthMode { signIn, signUp }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  String? _message;
  DateTime? _passwordResetRetryAt;
  DateTime? _confirmationResendRetryAt;
  Timer? _confirmationCooldownTimer;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _confirmationCooldownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startConfirmationCooldownTicker() {
    _confirmationCooldownTimer?.cancel();
    if (_confirmationResendRetryAt == null) {
      return;
    }

    _confirmationCooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final retryAt = _confirmationResendRetryAt;
        if (retryAt == null || DateTime.now().isAfter(retryAt)) {
          timer.cancel();
          setState(() {
            _confirmationResendRetryAt = null;
          });
          return;
        }

        setState(() {});
      },
    );
  }

  Future<void> _submit() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
      final settings = context.appSettings;
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text.trim();
      final emailRedirectTo = _authEmailRedirectUrl();
      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

      if (!emailRegex.hasMatch(email)) {
        setState(() {
          _error = settings.tx('Enter a valid email address.', 'اكتب إيميل صحيح.');
          _loading = false;
        });
        return;
      }

      if (password.isEmpty) {
        setState(() {
          _error = settings.tx('Enter your password.', 'اكتب كلمة السر.');
          _loading = false;
        });
        return;
      }

      if (_mode == _AuthMode.signUp && password.length < 6) {
        setState(() {
          _error = settings.tx(
            'Password must be at least 6 characters.',
            'كلمة السر لازم تكون ٦ حروف على الأقل.',
          );
          _loading = false;
        });
        return;
      }

      if (_mode == _AuthMode.signUp) {
        final result = await _client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: emailRedirectTo,
        );

        if (!mounted) {
          return;
        }

        if (result.session == null) {
          setState(() {
            _message = settings.tx(
              'Account created. Confirm your email, then sign in.',
              'الحساب اتعمل. أكّد الإيميل وبعدها سجّل دخول.',
            );
          });
        }
      } else {
        await _client.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (error) {
      final settings = context.appSettings;
      final retryAfterSeconds = _resolveEmailRateLimitSeconds(error.message);
      if (_mode == _AuthMode.signUp && retryAfterSeconds != null) {
        _confirmationResendRetryAt = DateTime.now().add(
          Duration(seconds: retryAfterSeconds),
        );
        _startConfirmationCooldownTicker();
      }

      setState(() {
        _error = retryAfterSeconds != null && _mode == _AuthMode.signUp
            ? settings.tx(
                'Email sending is temporarily limited. Please wait $retryAfterSeconds seconds, then try again.',
                'إرسال الإيميل متوقف مؤقتًا بسبب عدد الطلبات. استنى $retryAfterSeconds ثانية وجرب تاني.',
              )
            : error.message;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
      final redirectTo = kIsWeb
          ? _webRedirectUrl()
          : 'io.supabase.flutter://login-callback';

      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
    } on AuthException catch (error) {
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final settings = context.appSettings;
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    var dialogLoading = false;
    String? dialogError;

    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                settings.tx('Reset password', 'إعادة تعيين كلمة السر'),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    settings.tx(
                      'Enter your email and we will send reset instructions.',
                      'اكتب الإيميل وهنبعتلك خطوات إعادة التعيين.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !dialogLoading,
                    decoration: InputDecoration(
                      labelText: settings.tx('Email', 'الإيميل'),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: dialogLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(settings.tx('Cancel', 'إلغاء')),
                ),
                ElevatedButton(
                  onPressed: dialogLoading
                      ? null
                      : () async {
                          final now = DateTime.now();
                          if (_passwordResetRetryAt != null &&
                              now.isBefore(_passwordResetRetryAt!)) {
                            final waitSeconds = _passwordResetRetryAt!
                                .difference(now)
                                .inSeconds;
                            setDialogState(() {
                              dialogError = settings.tx(
                                'Too many reset attempts. Please wait about ${waitSeconds + 1}s and try again.',
                                'محاولات كتير. استنى حوالي ${waitSeconds + 1} ثانية وجرب تاني.',
                              );
                            });
                            return;
                          }

                          final email = emailController.text.trim();
                          if (!emailRegex.hasMatch(email)) {
                            setDialogState(() {
                              dialogError = settings.tx(
                                'Enter a valid email address.',
                                'اكتب إيميل صحيح.',
                              );
                            });
                            return;
                          }

                          setDialogState(() {
                            dialogLoading = true;
                            dialogError = null;
                          });

                          try {
                            await _client.auth.resetPasswordForEmail(
                              email,
                              redirectTo: _authEmailRedirectUrl(),
                            );
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            setState(() {
                              _message = settings.tx(
                                'Password reset email sent. Check your inbox.',
                                'تم إرسال رسالة إعادة التعيين. راجع بريدك.',
                              );
                              _error = null;
                            });
                          } on AuthException catch (error) {
                            final rawMessage = error.message.toLowerCase();
                            if (rawMessage.contains('rate limit')) {
                              _passwordResetRetryAt = DateTime.now().add(
                                const Duration(seconds: 60),
                              );
                            }

                            setDialogState(() {
                              dialogLoading = false;
                              dialogError = rawMessage.contains('rate limit')
                                  ? settings.tx(
                                      'Too many reset requests right now. Please wait 60 seconds, then try again.',
                                      'طلبات إعادة تعيين كتير دلوقتي. استنى 60 ثانية وجرب تاني.',
                                    )
                                  : error.message;
                            });
                          } catch (error) {
                            setDialogState(() {
                              dialogLoading = false;
                              dialogError = error.toString();
                            });
                          }
                        },
                  child: dialogLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(settings.tx('Send link', 'إرسال الرابط')),
                ),
              ],
            );
          },
        );
      },
    );

    emailController.dispose();
  }

  Future<void> _resendConfirmationEmail() async {
    if (_loading) {
      return;
    }

    final settings = context.appSettings;
    final now = DateTime.now();
    if (_confirmationResendRetryAt != null &&
        now.isBefore(_confirmationResendRetryAt!)) {
      final waitSeconds = _confirmationResendRetryAt!.difference(now).inSeconds;
      setState(() {
        _error = settings.tx(
          'For security, wait about ${waitSeconds + 1}s before requesting another confirmation email.',
          'للأمان، استنى حوالي ${waitSeconds + 1} ثانية قبل طلب رسالة تأكيد جديدة.',
        );
        _message = null;
      });
      return;
    }

    final email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (!emailRegex.hasMatch(email)) {
      setState(() {
        _error = settings.tx('Enter a valid email address.', 'اكتب إيميل صحيح.');
        _message = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: _authEmailRedirectUrl(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _confirmationResendRetryAt = DateTime.now().add(
          const Duration(seconds: 60),
        );
        _startConfirmationCooldownTicker();
        _message = settings.tx(
          'Confirmation email resent. Check inbox and spam.',
          'اتبعت رسالة تأكيد جديدة. راجع الوارد والسبام.',
        );
      });
    } on AuthException catch (error) {
      final retryAfterSeconds = _resolveEmailRateLimitSeconds(error.message);
      if (retryAfterSeconds != null) {
        _confirmationResendRetryAt = DateTime.now().add(
          Duration(seconds: retryAfterSeconds),
        );
        _startConfirmationCooldownTicker();
      }

      setState(() {
        _error = retryAfterSeconds != null
            ? settings.tx(
                'Too many confirmation requests. Please wait $retryAfterSeconds seconds, then try again.',
                'طلبات التأكيد كتير. استنى $retryAfterSeconds ثانية وجرب تاني.',
              )
            : error.message;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _authEmailRedirectUrl() {
    if (kIsWeb) {
      return _webRedirectUrl();
    }
    return 'io.supabase.flutter://login-callback';
  }

  String _webRedirectUrl() {
    final base = Uri.base;
    final portPart = base.hasPort ? ':${base.port}' : '';
    return '${base.scheme}://${base.host}$portPart';
  }

  int? _extractRetryAfterSeconds(String message) {
    final match = RegExp(r'after\s+(\d+)\s+seconds', caseSensitive: false)
        .firstMatch(message);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  int? _resolveEmailRateLimitSeconds(String message) {
    final parsedSeconds = _extractRetryAfterSeconds(message);
    if (parsedSeconds != null) {
      return parsedSeconds;
    }

    final lower = message.toLowerCase();
    if (lower.contains('rate limit') || lower.contains('too many requests')) {
      return 60;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final resendWaitSeconds = _confirmationResendRetryAt == null
        ? 0
        : _confirmationResendRetryAt!
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 9999);
    final canResendNow = resendWaitSeconds == 0;

    return Scaffold(
      body: TopologicalBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'LiftTier',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                color: primary,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          settings.tx(
                            'Track your lifts. Claim your tier.',
                            'سجّل رفعاتك واثبت مستواك.',
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonal(
                                onPressed: _loading
                                    ? null
                                    : () {
                                        setState(() {
                                          _mode = _AuthMode.signIn;
                                          _error = null;
                                          _message = null;
                                        });
                                      },
                                style: FilledButton.styleFrom(
                                  backgroundColor: _mode == _AuthMode.signIn
                                      ? primary
                                      : AppColors.surfaceHighest,
                                  foregroundColor: _mode == _AuthMode.signIn
                                      ? Colors.black
                                      : AppColors.onSurface,
                                ),
                                child: Text(
                                  settings.tx('SIGN IN', 'تسجيل دخول'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonal(
                                onPressed: _loading
                                    ? null
                                    : () {
                                        setState(() {
                                          _mode = _AuthMode.signUp;
                                          _error = null;
                                          _message = null;
                                        });
                                      },
                                style: FilledButton.styleFrom(
                                  backgroundColor: _mode == _AuthMode.signUp
                                      ? primary
                                      : AppColors.surfaceHighest,
                                  foregroundColor: _mode == _AuthMode.signUp
                                      ? Colors.black
                                      : AppColors.onSurface,
                                ),
                                child: Text(
                                  settings.tx('SIGN UP', 'اعمل حساب'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_error != null) ...[
                          _InlineNotice(
                            text: _error!,
                            borderColor: errorColor.withValues(alpha: 0.4),
                            fillColor: errorColor.withValues(alpha: 0.1),
                            textColor: errorColor,
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (_message != null) ...[
                          _InlineNotice(
                            text: _message!,
                            borderColor: primary.withValues(alpha: 0.4),
                            fillColor: primary.withValues(alpha: 0.12),
                            textColor: primary,
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: settings.tx('Email', 'الإيميل'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: _mode == _AuthMode.signUp
                                ? settings.tx(
                                    'Password (minimum 6 chars)',
                                    'كلمة السر (٦ حروف على الأقل)',
                                  )
                                : settings.tx('Password', 'كلمة السر'),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              tooltip: _obscurePassword
                                  ? settings.tx('Show password', 'إظهار كلمة السر')
                                  : settings.tx('Hide password', 'إخفاء كلمة السر'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading ? null : _showForgotPasswordDialog,
                            child: Text(
                              settings.tx('Forgot Password?', 'نسيت كلمة السر؟'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : Text(
                                  _mode == _AuthMode.signUp
                                      ? settings.tx(
                                          'CREATE ACCOUNT',
                                          'إنشاء حساب',
                                        )
                                      : settings.tx('SIGN IN', 'تسجيل دخول'),
                                ),
                        ),
                        if (_mode == _AuthMode.signUp) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _loading || !canResendNow
                                ? null
                                : _resendConfirmationEmail,
                            child: Text(
                              canResendNow
                                  ? settings.tx(
                                      'Resend confirmation email',
                                      'إعادة إرسال إيميل التأكيد',
                                    )
                                  : settings.tx(
                                      'Resend confirmation email (${resendWaitSeconds + 1}s)',
                                      'إعادة إرسال إيميل التأكيد (${resendWaitSeconds + 1}ث)',
                                    ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _signInWithGoogle,
                          icon: const Icon(Icons.g_mobiledata_rounded),
                          label: Text(
                            settings.tx(
                              'Continue with Google',
                              'كمّل بـ Google',
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.onSurface,
                            side: BorderSide(
                              color: AppColors.outline.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.text,
    required this.borderColor,
    required this.fillColor,
    required this.textColor,
  });

  final String text;
  final Color borderColor;
  final Color fillColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: fillColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: textColor),
      ),
    );
  }
}
