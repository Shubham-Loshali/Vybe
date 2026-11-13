import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/utilities/flutter_toast.dart';

const _green = Color(0xFF1ED760);
const _muted = Color(0xFFB3B3B3);

enum _AuthAction { email, google, reset }

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key, this.initiallySignUp = true, this.service});

  final bool initiallySignUp;
  final CloudSyncService? service;

  static Future<void> show(
    BuildContext context, {
    bool initiallySignUp = true,
  }) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierDismissible: false,
      builder: (_) => AuthDialog(initiallySignUp: initiallySignUp),
    );
  }

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailFieldKey = GlobalKey<FormFieldState<String>>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _scrollController = ScrollController();
  late bool _isSignUp;
  bool _obscurePassword = true;
  _AuthAction? _pendingAction;
  String? _errorMessage;
  String? _infoMessage;

  bool get _isLoading => _pendingAction != null;
  CloudSyncService get _service => widget.service ?? CloudSyncService.instance;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.initiallySignUp;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startLoading(_AuthAction action) {
    FocusScope.of(context).unfocus();
    setState(() {
      _pendingAction = action;
      _errorMessage = null;
      _infoMessage = null;
    });
  }

  void _switchMode() {
    if (_isLoading) return;
    // Clear validation without discarding the credentials already entered.
    final email = _emailController.value;
    final password = _passwordController.value;
    _formKey.currentState?.reset();
    _emailController.value = email;
    _passwordController.value = password;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSignUp = !_isSignUp;
      _obscurePassword = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _skip() async {
    if (_isLoading) return;
    await Hive.box('settings').put('auth_prompt_dismissed', true);
    if (mounted) Navigator.of(context).pop();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    _startLoading(_AuthAction.google);
    final success = await _service.signInWithGoogle();
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (success) {
      TextInput.finishAutofillContext();
      Navigator.of(context).pop();
      showToast(context, 'Signed in successfully! Restoring data...');
    } else {
      final message = _service.syncMessage.value;
      if (message != null &&
          message.isNotEmpty &&
          !message.toLowerCase().contains('cancelled')) {
        setState(() => _errorMessage = message);
      }
    }
  }

  Future<void> _handleEmailAuth() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    // Spaces can be part of an existing account's password.
    final password = _passwordController.text;
    final isSignUp = _isSignUp;
    _startLoading(_AuthAction.email);
    final service = _service;
    final success = isSignUp
        ? await service.signUpWithEmail(email, password)
        : await service.signInWithEmail(email, password);
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (success && isSignUp) {
      setState(() {
        _isSignUp = false;
        _obscurePassword = true;
        _infoMessage =
            'We sent a verification link to $email. '
            'Check your inbox or spam folder, verify your email, then log in.';
      });
    } else if (success) {
      TextInput.finishAutofillContext();
      Navigator.of(context).pop();
      showToast(context, 'Signed in successfully! Welcome back');
    } else {
      setState(() {
        _errorMessage =
            service.syncMessage.value ??
            (isSignUp
                ? 'Could not create your account. Please try again.'
                : 'Could not log in. Check your email and password.');
      });
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_isLoading || !_emailFieldKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    _startLoading(_AuthAction.reset);
    final success = await _service.sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _pendingAction = null;
      if (success) {
        _infoMessage =
            'We sent a password reset link to $email. '
            'Check your inbox to choose a new password.';
      } else {
        _errorMessage =
            _service.syncMessage.value ??
            'Could not send a reset link. Please try again.';
      }
    });
  }

  InputDecoration _decoration(String hint) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF929292), fontSize: 15),
      filled: true,
      fillColor: const Color(0xFF181818),
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      enabledBorder: border(const Color(0xFF727272)),
      disabledBorder: border(const Color(0xFF404040)),
      focusedBorder: border(_green, 2),
      errorBorder: border(const Color(0xFFFF9099)),
      focusedErrorBorder: border(const Color(0xFFFF9099), 2),
      errorStyle: const TextStyle(color: Color(0xFFFF9099), fontSize: 12),
      errorMaxLines: 3,
    );
  }

  Widget _spinner({Color color = Colors.black}) => SizedBox.square(
    dimension: 21,
    child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
  );

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return PopScope(
      canPop: !_isLoading,
      child: Dialog.fullscreen(
        backgroundColor: surface,
        child: Scaffold(
          backgroundColor: surface,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFF15261B), surface, surface],
                stops: const [0, 0.38, 1],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                key: const ValueKey('auth-scroll'),
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                ClipOval(
                                  child: Image.asset(
                                    'assets/icons/vybe_icon.png',
                                    width: 36,
                                    height: 36,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Vybe',
                                    style: TextStyle(
                                      fontFamily: 'paytoneOne',
                                      fontSize: 25,
                                      color: Colors.white,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _isLoading ? null : _skip,
                                  style: TextButton.styleFrom(
                                    foregroundColor: _muted,
                                    minimumSize: const Size(48, 48),
                                  ),
                                  child: const Text('Skip for now'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Semantics(
                              header: true,
                              child: Text.rich(
                                TextSpan(
                                  text: _isSignUp
                                      ? 'Your music.\n'
                                      : 'Welcome\n',
                                  children: [
                                    TextSpan(
                                      text: _isSignUp ? 'Your Vybe.' : 'back.',
                                      style: const TextStyle(color: _green),
                                    ),
                                  ],
                                ),
                                style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800,
                                  height: 1.06,
                                  letterSpacing: -1.8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _isSignUp
                                  ? 'Sign up to keep your playlists and likes\nwith you, wherever you listen.'
                                  : 'Your playlists and likes are waiting.\nPick up where you left off.',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 30),
                            const _FieldLabel('Email address'),
                            const SizedBox(height: 8),
                            Semantics(
                              label: 'Email address',
                              child: TextFormField(
                                key: _emailFieldKey,
                                controller: _emailController,
                                enabled: !_isLoading,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                autocorrect: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                decoration: _decoration('name@example.com'),
                                validator: _validateEmail,
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const _FieldLabel('Password'),
                            const SizedBox(height: 8),
                            Semantics(
                              label: 'Password',
                              child: TextFormField(
                                key: const ValueKey('auth-password'),
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                enabled: !_isLoading,
                                obscureText: _obscurePassword,
                                autocorrect: false,
                                enableSuggestions: false,
                                textInputAction: TextInputAction.done,
                                autofillHints: [
                                  if (_isSignUp)
                                    AutofillHints.newPassword
                                  else
                                    AutofillHints.password,
                                ],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                decoration:
                                    _decoration(
                                      _isSignUp
                                          ? 'Create a password'
                                          : 'Enter your password',
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePassword
                                            ? 'Show password'
                                            : 'Hide password',
                                        onPressed: _isLoading
                                            ? null
                                            : () => setState(
                                                () => _obscurePassword =
                                                    !_obscurePassword,
                                              ),
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: _muted,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                validator: (value) {
                                  if (value == null || value.isEmpty)
                                    return 'Enter your password.';
                                  if (_isSignUp && value.length < 6)
                                    return 'Use at least 6 characters.';
                                  return null;
                                },
                                onFieldSubmitted: (_) => _handleEmailAuth(),
                              ),
                            ),
                            if (_isSignUp)
                              const Padding(
                                padding: EdgeInsets.only(top: 9),
                                child: Text(
                                  'Use at least 6 characters.',
                                  style: TextStyle(fontSize: 12, color: _muted),
                                ),
                              )
                            else
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _handleForgotPassword,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(48, 48),
                                  ),
                                  child: _pendingAction == _AuthAction.reset
                                      ? _spinner(color: _green)
                                      : const Text(
                                          'Forgot password?',
                                          style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                ),
                              ),
                            if (_infoMessage != null || _errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: _AuthNotice(
                                  isError: _errorMessage != null,
                                  message: _errorMessage ?? _infoMessage!,
                                ),
                              ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _isLoading ? null : _handleEmailAuth,
                              style: FilledButton.styleFrom(
                                backgroundColor: _green,
                                foregroundColor: Colors.black,
                                disabledBackgroundColor: _green.withValues(
                                  alpha: 0.45,
                                ),
                                disabledForegroundColor: Colors.black,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontFamily: 'Figtree',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: _pendingAction == _AuthAction.email
                                  ? _spinner()
                                  : Text(
                                      _isSignUp ? 'Create account' : 'Log in',
                                    ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 22),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Divider(color: Color(0xFF363636)),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Text(
                                      'or',
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(color: Color(0xFF363636)),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : _handleGoogleSignIn,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                side: const BorderSide(
                                  color: Color(0xFF727272),
                                ),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontFamily: 'Figtree',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              icon: _pendingAction == _AuthAction.google
                                  ? _spinner(color: Colors.white)
                                  : const SizedBox.square(
                                      dimension: 20,
                                      child: CustomPaint(
                                        painter: _GoogleMarkPainter(),
                                      ),
                                    ),
                              label: const Text(
                                'Continue with Google',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 26),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 3,
                              children: [
                                Text(
                                  _isSignUp
                                      ? 'Already have an account?'
                                      : 'New to Vybe?',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 14,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _isLoading ? null : _switchMode,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(
                                    _isSignUp ? 'Log in' : 'Sign up free',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _AuthNotice extends StatelessWidget {
  const _AuthNotice({required this.message, required this.isError});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFFF9099) : _green;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.mark_email_read_outlined,
              color: color,
              size: 21,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isError ? 'Let’s try that again' : 'Check your inbox',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20, size.height / 20);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.7;
    const bounds = Rect.fromLTWH(2.3, 2.3, 15.4, 15.4);
    for (final segment in const [
      (Color(0xFF4285F4), 0.0, 45.0),
      (Color(0xFF34A853), 45.0, 90.0),
      (Color(0xFFFBBC05), 135.0, 65.0),
      (Color(0xFFEA4335), 200.0, 112.0),
    ]) {
      paint.color = segment.$1;
      canvas.drawArc(
        bounds,
        segment.$2 * math.pi / 180,
        segment.$3 * math.pi / 180,
        false,
        paint,
      );
    }
    canvas.drawRect(
      const Rect.fromLTWH(10, 8.2, 9.4, 3.7),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(_GoogleMarkPainter oldDelegate) => false;
}
