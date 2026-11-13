import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/utilities/flutter_toast.dart';

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) => const AuthDialog(),
    );
  }

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSignUp = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final success = await CloudSyncService.instance.signInWithGoogle();
    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pop();
      showToast(context, 'Signed in successfully! Restoring data...');
    } else {
      final msg = CloudSyncService.instance.syncMessage.value;
      if (msg != null && msg.isNotEmpty && !msg.contains('cancelled')) {
        setState(() => _errorMessage = msg);
      }
    }
  }

  Future<void> _handleEmailAuth({required bool isSignUp}) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both email and password';
        _infoMessage = null;
      });
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
        _infoMessage = null;
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters';
        _infoMessage = null;
      });
      return;
    }

    if (isSignUp) {
      final confirmPassword = _confirmPasswordController.text.trim();
      if (confirmPassword != password) {
        setState(() {
          _errorMessage = 'Passwords do not match';
          _infoMessage = null;
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    if (isSignUp) {
      final name = _nameController.text.trim();
      final success = await CloudSyncService.instance.signUpWithEmail(
        email,
        password,
        displayName: name.isNotEmpty ? name : null,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        setState(() {
          _isSignUp = false;
          _infoMessage =
              'Verification link sent to $email!\n\nPlease check your inbox and click the verification link, then sign in below.';
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = CloudSyncService.instance.syncMessage.value ??
              'Account creation failed. Please try again.';
        });
      }
    } else {
      final success =
          await CloudSyncService.instance.signInWithEmail(email, password);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        Navigator.of(context).pop();
        showToast(context, 'Signed in successfully! Welcome back');
      } else {
        setState(() {
          _errorMessage = CloudSyncService.instance.syncMessage.value ??
              'Sign in failed. Check your credentials.';
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your email above to receive a password reset link';
        _infoMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final success = await CloudSyncService.instance.sendPasswordReset(email);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      setState(() {
        _infoMessage = 'Password reset link sent to $email! Check your inbox.';
      });
    } else {
      setState(() {
        _errorMessage = CloudSyncService.instance.syncMessage.value ??
            'Failed to send password reset email';
      });
    }
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0C1A11).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(30),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: const Color(0xFF1ED760),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF7E8F84),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: const Color(0xFF9EABA2),
            size: 20,
          ),
          suffixIcon: suffixIcon,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(
              color: const Color(0xFF1ED760).withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(
              color: const Color(0xFF1ED760).withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(
              color: Color(0xFF1ED760),
              width: 1.8,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      elevation: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2618),
                  Color(0xFF07120B),
                  Color(0xFF09190F),
                  Color(0xFF0C1D13),
                ],
                stops: [0.0, 0.45, 0.8, 1.0],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: const Color(0xFF1ED760).withValues(alpha: 0.65),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1ED760).withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 36,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                children: [
                  // Subtle ambient background light
                  Positioned(
                    top: -50,
                    right: -50,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1ED760).withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -60,
                    left: -50,
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1ED760).withValues(alpha: 0.08),
                      ),
                    ),
                  ),

                  // Main Scrollable Body
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Row with mascot & close button
                        Row(
                          children: [
                            // Mascot avatar badge
                            Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1ED760)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/icons/auth_ghost_badge.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Title & Subtitle
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isSignUp
                                        ? 'Create Account'
                                        : 'Welcome Back',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _isSignUp
                                        ? 'Join Vybe and never miss a beat!'
                                        : 'Sign in and never miss a beat!',
                                    style: const TextStyle(
                                      color: Color(0xFF9EABA2),
                                      fontSize: 12.5,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Close Button
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                                size: 21,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Form Fields
                        if (_isSignUp) ...[
                          _buildInputField(
                            controller: _nameController,
                            hintText: 'Full Name',
                            prefixIcon: Icons.person_outline,
                          ),
                          const SizedBox(height: 12),
                        ],

                        _buildInputField(
                          controller: _emailController,
                          hintText: 'Email Address',
                          prefixIcon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),

                        _buildInputField(
                          controller: _passwordController,
                          hintText: 'Password',
                          prefixIcon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF9EABA2),
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),

                        if (_isSignUp) ...[
                          const SizedBox(height: 12),
                          _buildInputField(
                            controller: _confirmPasswordController,
                            hintText: 'Confirm Password',
                            prefixIcon: Icons.lock_outline,
                            obscureText: _obscureConfirmPassword,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: const Color(0xFF9EABA2),
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                            ),
                          ),
                        ],

                        if (!_isSignUp) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _handleForgotPassword,
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                              ),
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9EABA2),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                        ],

                        // Error / Info banners
                        if (_infoMessage != null) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1ED760).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF1ED760).withValues(alpha: 0.45),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  FluentIcons.mail_alert_24_regular,
                                  color: Color(0xFF1ED760),
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _infoMessage!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        if (_errorMessage != null) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE91429).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE91429).withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFFF7A88),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],

                        // Primary Action Button (Sign Up -> / Sign In ->)
                        GestureDetector(
                          onTap: _isLoading
                              ? null
                              : () => _handleEmailAuth(isSignUp: _isSignUp),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF22E56B), Color(0xFF1DB954)],
                              ),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1ED760)
                                      .withValues(alpha: 0.45),
                                  blurRadius: 18,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _isSignUp ? 'Sign Up' : 'Sign In',
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Colors.black,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Divider with 'or'
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: const Color(0xFF1ED760)
                                    .withValues(alpha: 0.22),
                                thickness: 1,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'or',
                                style: TextStyle(
                                  color: Color(0xFF7E8F84),
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: const Color(0xFF1ED760)
                                    .withValues(alpha: 0.22),
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Google Sign-In Button
                        GestureDetector(
                          onTap: _isLoading ? null : _handleGoogleSignIn,
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C1A11)
                                  .withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: const Color(0xFF1ED760)
                                    .withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const _GoogleIcon(),
                                const SizedBox(width: 10),
                                Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Switch between Sign Up & Sign In
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _isSignUp
                                  ? 'Already have an account? '
                                  : "Don't have an account? ",
                              style: const TextStyle(
                                color: Color(0xFF9EABA2),
                                fontSize: 13,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                  _errorMessage = null;
                                  _infoMessage = null;
                                });
                              },
                              child: Text(
                                _isSignUp ? 'Sign In' : 'Sign Up',
                                style: const TextStyle(
                                  color: Color(0xFF1ED760),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Skip for now
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              Hive.box('settings')
                                  .put('auth_prompt_dismissed', true);
                              Navigator.of(context).pop();
                            },
                            child: const Text(
                              'Skip for now',
                              style: TextStyle(
                                color: Color(0xFF7E8F84),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;
    final strokeWidth = w * 0.22;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );

    // Red (top)
    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi * 0.75, math.pi * 0.52, false, redPaint);

    // Yellow (left)
    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, math.pi * 0.75, math.pi * 0.52, false, yellowPaint);

    // Green (bottom)
    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, math.pi * 0.25, math.pi * 0.52, false, greenPaint);

    // Blue (right)
    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi * 0.25, math.pi * 0.52, false, bluePaint);

    // Blue horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - strokeWidth * 0.1,
        center.dy - strokeWidth / 2,
        radius * 0.95,
        strokeWidth,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
