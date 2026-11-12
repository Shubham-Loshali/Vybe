import 'package:material_ui/material_ui.dart';

class PlaylistSliverAppBar extends StatelessWidget {
  const PlaylistSliverAppBar({
    super.key,
    required this.title,
    required this.artwork,
    this.leading,
  });

  final String title;
  final Widget artwork;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final pageColor = Theme.of(context).scaffoldBackgroundColor;
    // Spotify tints the header with the cover's colour; derive a stable tint
    // from the title so every playlist gets its own backdrop.
    final hash = title.codeUnits.fold<int>(
      7,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    final tint = HSLColor.fromAHSL(
      1,
      (hash % 360).toDouble(),
      0.42,
      0.30,
    ).toColor();

    return SliverAppBar(
      leading: leading,
      pinned: true,
      expandedHeight: screenSize.width > screenSize.height ? 380 : 340,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        expandedTitleScale: 1.35,
        titlePadding: const EdgeInsetsDirectional.only(
          start: 64,
          end: 64,
          bottom: 16,
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: 0,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        background: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [tint, pageColor],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 56, bottom: 64),
            child: Center(child: artwork),
          ),
        ),
      ),
    );
  }
}
