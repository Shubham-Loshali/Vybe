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
      builder: (_) => const AuthDialog(),
    );
  }

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    if (isSignUp) {
      final success =
          await CloudSyncService.instance.signUpWithEmail(email, password);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        setState(() {
          _infoMessage =
              'Verification link sent to $email!\n\nPlease check your inbox (or spam) and click the verification link, then tap "Sign In" below.';
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = CloudSyncService.instance.syncMessage.value ??
              'Account creation failed. Please check the email and try again.';
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            FluentIcons.cloud_sync_24_filled,
            color: colorScheme.primary,
            size: 26,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sign in to Vybe',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sync playlists and likes so you never lose them.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),

            // Google Sign-In Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
              ),
              onPressed: _isLoading ? null : _handleGoogleSignIn,
              icon: const Icon(Icons.account_circle, size: 20),
              label: const Text(
                'Continue with Google',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),

            // Divider
            Row(
              children: [
                Expanded(
                  child: Divider(color: colorScheme.outline.withValues(alpha: 0.3)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or email',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: colorScheme.outline.withValues(alpha: 0.3)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Email Field
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Password Field
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            if (_infoMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      FluentIcons.mail_alert_24_regular,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _infoMessage!,
                        style: TextStyle(
                          color: colorScheme.onSurface,
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
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _handleForgotPassword,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),

            if (_isLoading) ...[
              const SizedBox(height: 10),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ],
          ],
        ),
      ),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          onPressed: () {
            Hive.box('settings').put('auth_prompt_dismissed', true);
            Navigator.of(context).pop();
          },
          child: Text(
            'Skip for now',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        TextButton(
          onPressed: _isLoading ? null : () => _handleEmailAuth(isSignUp: true),
          child: const Text('Create Account'),
        ),
        FilledButton(
          onPressed:
              _isLoading ? null : () => _handleEmailAuth(isSignUp: false),
          child: const Text('Sign In'),
        ),
      ],
    );
  }
}
