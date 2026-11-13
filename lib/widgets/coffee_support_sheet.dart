import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vybe/constants/support.dart';
import 'package:vybe/main.dart' show logger;

class CoffeeSupportSheet extends StatefulWidget {
  const CoffeeSupportSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.black,
    builder: (_) => const CoffeeSupportSheet(),
  );

  @override
  State<CoffeeSupportSheet> createState() => _CoffeeSupportSheetState();
}

class _CoffeeSupportSheetState extends State<CoffeeSupportSheet> {
  bool _isOpening = false;
  bool _copied = false;
  String? _message;

  Future<void> _copyId() async {
    try {
      await Clipboard.setData(const ClipboardData(text: supportUpiId));
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Couldn’t copy the ID. Press and hold it to copy.',
        );
      }
    }
  }

  Future<void> _openUpiApp() async {
    if (_isOpening) return;
    setState(() {
      _isOpening = true;
      _message = null;
    });
    try {
      final opened = await launchUrl(
        coffeePaymentUri(),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(
          () => _message = 'Couldn’t open a UPI app. Copy the ID and pay from your preferred app.',
        );
      }
    } catch (error, stackTrace) {
      logger.log(
        'Could not open UPI support request',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(
          () => _message = 'Couldn’t open a UPI app. Copy the ID and pay from your preferred app.',
        );
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  FluentIcons.drink_coffee_24_regular,
                  color: colors.primary,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Buy us a coffee',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Choose any amount and confirm your payment in your UPI app.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UPI ID',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(
                    supportUpiId,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    supportPayeeName,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_message != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: const TextStyle(color: Color(0xFFFFB4A9), height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _isOpening ? null : _openUpiApp,
              icon: _isOpening
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                      ),
                    )
                  : const Icon(FluentIcons.open_24_regular, size: 20),
              label: const Text('Open UPI app', textAlign: TextAlign.center),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _copyId,
              icon: Icon(
                _copied
                    ? FluentIcons.checkmark_24_regular
                    : FluentIcons.copy_24_regular,
                size: 20,
              ),
              label: Text(
                _copied ? 'UPI ID copied' : 'Copy UPI ID',
                textAlign: TextAlign.center,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _copied ? colors.primary : colors.onSurface,
                side: BorderSide(color: colors.outline),
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
