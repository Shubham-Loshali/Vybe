import 'package:firebase_auth/firebase_auth.dart';

/// Derive the greeting from the active account, never a device-wide setting.
String accountFirstName(User? user) {
  if (user == null || user.isAnonymous || !user.emailVerified) return '';

  final displayName = user.displayName?.trim() ?? '';
  if (displayName.isNotEmpty) {
    return displayName.split(RegExp(r'\s+')).first;
  }

  // Email accounts do not collect a display name during sign-up.
  final emailName = (user.email?.trim() ?? '').split('@').first;
  final firstName = emailName.split(RegExp(r'[._+\-]')).first;
  if (firstName.isEmpty) return '';
  return firstName[0].toUpperCase() + firstName.substring(1);
}
