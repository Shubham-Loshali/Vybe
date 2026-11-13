import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

/// Public-facing messages only. The original exception belongs in the log.
/// A null message means the user cancelled, rather than sign-in failing.
String? googleSignInErrorMessage(Object error) {
  const configurationMessage =
      'Google sign-in isn’t available for this version yet. '
      'You can still sign up or log in with email.';
  const networkMessage =
      'Couldn’t connect to Google. Check your connection and try again.';

  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (const {
      'sign_in_canceled',
      'sign_in_cancelled',
      'canceled',
      'cancelled',
    }.contains(code)) {
      return null;
    }
    final details = '${error.message ?? ''} ${error.details ?? ''}';
    if (code == 'client_configuration_error' ||
        RegExp(
          r'ApiException:\s*10\b|DEVELOPER_ERROR|serverClientId',
          caseSensitive: false,
        ).hasMatch(details)) {
      return configurationMessage;
    }
    if (code == 'network_error' ||
        RegExp(r'ApiException:\s*7\b').hasMatch(details)) {
      return networkMessage;
    }
  }

  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'network-request-failed':
        return networkMessage;
      case 'operation-not-allowed':
        return configurationMessage;
      case 'account-exists-with-different-credential':
        return 'An account already exists for this email. '
            'Log in using the method you used to create it.';
      case 'too-many-requests':
        return 'Too many sign-in attempts. Please wait a moment and try again.';
    }
  }

  return 'Couldn’t sign in with Google. Please try again or use email.';
}
