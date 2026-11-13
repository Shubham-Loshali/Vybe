import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vybe/constants/developers.dart';
import 'package:vybe/main.dart' show logger;
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/widgets/coffee_support_sheet.dart';
import 'package:vybe/widgets/mini_player_bottom_space.dart';

const _muted = Color(0xFFA9AFB8);
const _headphonesAsset = 'assets/images/developers/headphones.png';

class DevelopersPage extends StatelessWidget {
  const DevelopersPage({super.key});

  Future<void> _openProfile(BuildContext context, String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        showToast(context, 'Couldn’t open the profile. Please try again.');
      }
    } catch (error, stackTrace) {
      logger.log(
        'Could not open developer profile',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        showToast(context, 'Couldn’t open the profile. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.black,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        title: const Text(
          'Developers',
          style: TextStyle(fontFamily: 'Figtree'),
        ),
        actions: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(right: 22),
              child: SizedBox(
                width: 22,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: 3,
                      height: 12,
                      child: ColoredBox(color: green),
                    ),
                    SizedBox(
                      width: 3,
                      height: 22,
                      child: ColoredBox(color: green),
                    ),
                    SizedBox(
                      width: 3,
                      height: 15,
                      child: ColoredBox(color: green),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _MakersHero(),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stack =
                        constraints.maxWidth < 280 ||
                        MediaQuery.textScalerOf(context).scale(14) > 18;
                    final cards = [
                      for (final developer in developerProfiles)
                        _DeveloperCard(
                          developer: developer,
                          stackActions:
                              stack || (constraints.maxWidth - 14) / 2 < 154,
                          onGitHub: () =>
                              _openProfile(context, developer.githubUrl),
                          onLinkedIn: () =>
                              _openProfile(context, developer.linkedInUrl),
                        ),
                    ];
                    if (stack) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cards[0],
                          const SizedBox(height: 18),
                          cards[1],
                        ],
                      );
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 14),
                          Expanded(child: cards[1]),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 34),
                const _CoffeeCard(),
                const SizedBox(height: 12),
                const MiniPlayerBottomSpace(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MakersHero extends StatelessWidget {
  const _MakersHero();

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
        final compact = constraints.maxWidth < 330;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: largeText ? null : 245,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'THE DEVELOPERS BEHIND VYBE',
                      style: TextStyle(
                        color: green,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 40,
                    child: Divider(color: green.withValues(alpha: 0.3)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Meet the',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 38 : 44,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                height: 1,
              ),
            ),
            Text(
              'makers.',
              style: TextStyle(
                color: green,
                fontSize: compact ? 47 : 54,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.8,
                height: 1.03,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Built with a love for music.',
              style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
            ),
          ],
        );
        final artwork = Image.asset(
          _headphonesAsset,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        );
        if (largeText) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(width: 170, height: 180, child: artwork),
              ),
            ],
          );
        }
        return SizedBox(
          height: 190,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -18,
                top: -2,
                width: constraints.maxWidth * 0.51,
                height: 190,
                child: artwork,
              ),
              Positioned(left: 0, top: 15, child: copy),
            ],
          ),
        );
      },
    );
  }
}

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({
    required this.developer,
    required this.onGitHub,
    required this.onLinkedIn,
    required this.stackActions,
  });

  final DeveloperProfile developer;
  final VoidCallback onGitHub;
  final VoidCallback onLinkedIn;
  final bool stackActions;

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    final initials = developer.name.split(' ').map((part) => part[0]).join();
    return _NeonPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 22, 10, 12),
        child: Column(
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: 94,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.alphaBlend(
                          green.withValues(alpha: 0.05),
                          Colors.black,
                        ),
                        border: Border.all(color: green, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: green.withValues(alpha: 0.3),
                            blurRadius: 14,
                          ),
                          BoxShadow(
                            color: green.withValues(alpha: 0.12),
                            blurRadius: 3,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: developer.photoAsset == null
                          ? Text(
                              initials,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color: green,
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(2),
                              child: ClipOval(
                                child: Transform.scale(
                                  scale: developer.photoScale,
                                  alignment: Alignment(
                                    developer.photoAlignmentX,
                                    developer.photoAlignmentY,
                                  ),
                                  child: Image.asset(
                                    developer.photoAsset!,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      right: 0,
                      top: -1,
                      child: Icon(
                        FluentIcons.sparkle_20_filled,
                        color: green,
                        size: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              developer.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(child: Divider(color: green.withValues(alpha: 0.2))),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 7),
                  child: Text(
                    'Developer',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                Expanded(child: Divider(color: green.withValues(alpha: 0.2))),
              ],
            ),
            const SizedBox(height: 10),
            if (stackActions)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileButton(label: 'GitHub', onPressed: onGitHub),
                  const SizedBox(height: 6),
                  _ProfileButton(label: 'LinkedIn', onPressed: onLinkedIn),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _ProfileButton(label: 'GitHub', onPressed: onGitHub),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _ProfileButton(
                      label: 'LinkedIn',
                      onPressed: onLinkedIn,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.38),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        side: BorderSide(color: green.withValues(alpha: 0.35)),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: 'Figtree',
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (label == 'LinkedIn')
            Container(
              width: 14,
              height: 14,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF0A80C5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text(
                'in',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            )
          else
            Image.asset(
              'assets/images/developers/github.png',
              width: 14,
              height: 14,
              excludeFromSemantics: true,
            ),
          const SizedBox(width: 4),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _CoffeeCard extends StatelessWidget {
  const _CoffeeCard();

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return _NeonPanel(
      coffee: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(14) > 18;
                final copy = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Keep '),
                          TextSpan(
                            text: 'Vybe',
                            style: TextStyle(color: green),
                          ),
                          const TextSpan(text: ' brewing.'),
                        ],
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enjoying the music? A little support goes a long way.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                );
                final cup = Icon(
                  FluentIcons.drink_coffee_24_regular,
                  color: green,
                  size: 60,
                );
                if (largeText) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [cup, const SizedBox(height: 18), copy],
                  );
                }
                return Row(
                  children: [
                    cup,
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      width: 1,
                      height: 62,
                      color: green.withValues(alpha: 0.3),
                    ),
                    Expanded(child: copy),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Align(
              child: FilledButton(
                onPressed: () => CoffeeSupportSheet.show(context),
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.heart_24_filled, size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Buy us a coffee',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(width: 10),
                    Icon(FluentIcons.arrow_right_24_regular, size: 21),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeonPanel extends StatelessWidget {
  const _NeonPanel({required this.child, this.coffee = false});
  final Widget child;
  final bool coffee;

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            green,
            Color.alphaBlend(green.withValues(alpha: 0.6), Colors.black),
            Color.alphaBlend(green.withValues(alpha: 0.3), Colors.black),
            green,
          ],
          stops: [0, 0.3, 0.65, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: green.withValues(alpha: coffee ? 0.22 : 0.13),
            blurRadius: coffee ? 20 : 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(green.withValues(alpha: 0.24), Colors.black),
                  Color.alphaBlend(green.withValues(alpha: 0.05), Colors.black),
                  Color.alphaBlend(
                    green.withValues(alpha: 0.025),
                    Colors.black,
                  ),
                  Color.alphaBlend(green.withValues(alpha: 0.22), Colors.black),
                ],
                stops: [0, 0.35, 0.75, 1],
              ),
            ),
            child: CustomPaint(
              painter: _PanelArt(coffee: coffee, green: green),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelArt extends CustomPainter {
  const _PanelArt({required this.coffee, required this.green});
  final bool coffee;
  final Color green;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ribbon = Path();
    if (coffee) {
      ribbon
        ..moveTo(0, h * 0.71)
        ..cubicTo(w * 0.18, h * 0.75, w * 0.22, h * 1.1, w * 0.52, h * 0.94)
        ..cubicTo(w * 0.77, h * 0.8, w * 0.89, h * 0.6, w, h * 0.73)
        ..lineTo(w, h)
        ..lineTo(0, h);
    } else {
      ribbon
        ..moveTo(0, h * 0.4)
        ..cubicTo(w * 0.32, h * 0.25, w * 0.6, h * 0.2, w, h * 0.02)
        ..cubicTo(w * 0.85, h * 0.26, w * 0.42, h * 0.4, 0, h * 0.5);
    }
    ribbon.close();
    canvas.drawPath(
      ribbon,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            green.withValues(alpha: 0.22),
            green.withValues(alpha: 0.015),
          ],
        ).createShader(Offset.zero & size),
    );
    if (coffee) {
      final wave = Path()
        ..moveTo(0, h * 0.9)
        ..cubicTo(w * 0.24, h * 0.7, w * 0.4, h * 1.22, w * 0.76, h * 0.94)
        ..quadraticBezierTo(w * 0.94, h * 0.78, w, h * 0.86);
      canvas.drawPath(
        wave,
        Paint()
          ..color = green.withValues(alpha: 0.13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18,
      );
      final notes = TextPainter(textDirection: TextDirection.ltr);
      for (final position in [
        Offset(w * 0.07, h * 0.69),
        Offset(w * 0.91, h * 0.55),
      ]) {
        notes
          ..text = TextSpan(
            text: String.fromCharCode(
              FluentIcons.music_note_2_24_filled.codePoint,
            ),
            style: TextStyle(
              fontFamily: FluentIcons.music_note_2_24_filled.fontFamily,
              package: FluentIcons.music_note_2_24_filled.fontPackage,
              fontSize: 22,
              color: green.withValues(alpha: 0.3),
            ),
          )
          ..layout()
          ..paint(canvas, position);
      }
      notes.dispose();
    }
  }

  @override
  bool shouldRepaint(_PanelArt oldDelegate) =>
      oldDelegate.coffee != coffee || oldDelegate.green != green;
}
