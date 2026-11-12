import 'package:material_ui/material_ui.dart';

/// Spotify's "Browse all": colourful two-column genre tiles. Tapping a tile
/// hands its name to [onTap], which runs a normal search.
class BrowseAllGrid extends StatelessWidget {
  const BrowseAllGrid({super.key, required this.onTap});

  final ValueChanged<String> onTap;

  static const _genres = <(String, Color)>[
    ('Pop', Color(0xFFE13300)),
    ('Hip-Hop', Color(0xFFBC5900)),
    ('Bollywood', Color(0xFF8D67AB)),
    ('Punjabi', Color(0xFF477D95)),
    ('Rock', Color(0xFFE91429)),
    ('Indie', Color(0xFFE61E32)),
    ('Dance', Color(0xFFD84000)),
    ('Romance', Color(0xFFDC148C)),
    ('Party', Color(0xFF8C1932)),
    ('Workout', Color(0xFF777777)),
    ('Chill', Color(0xFF1E3264)),
    ('Sleep', Color(0xFF503750)),
    ('Devotional', Color(0xFFB06239)),
    ('Gaming', Color(0xFFBA5D07)),
    ('Jazz', Color(0xFF0D73EC)),
    ('Classical', Color(0xFF7D4B32)),
  ];

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 700 ? 4 : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 12),
          child: Text(
            'Browse all',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _genres.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 100,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final (name, color) = _genres[index];
            return Material(
              color: color,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(name),
                child: Stack(
                  children: [
                    Positioned(
                      right: -14,
                      bottom: -6,
                      child: Transform.rotate(
                        angle: 0.42,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
