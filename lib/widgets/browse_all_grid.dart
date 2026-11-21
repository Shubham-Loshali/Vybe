import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

class _GenreItem {
  const _GenreItem({
    required this.title,
    required this.color,
    required this.endColor,
    required this.imageUrl,
  });

  final String title;
  final Color color;
  final Color endColor;
  final String imageUrl;
}

/// Spotify's "Browse all": vibrant genre tiles with tilted cover pictures
/// and subtle gradients. Tapping a tile hands its name to [onTap].
class BrowseAllGrid extends StatelessWidget {
  const BrowseAllGrid({super.key, required this.onTap});

  final ValueChanged<String> onTap;

  static const _genres = <_GenreItem>[
    _GenreItem(
      title: 'Hindi',
      color: Color(0xFFDC148C),
      endColor: Color(0xFFB50F73),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caff5976b97bcf10d98acbae2cd',
    ),
    _GenreItem(
      title: 'Punjabi',
      color: Color(0xFFB02897),
      endColor: Color(0xFF8B1D77),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf4f1aa71a9cdcffdf8430c070',
    ),
    _GenreItem(
      title: 'Tamil',
      color: Color(0xFFBA5D07),
      endColor: Color(0xFF944804),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005cafae68f35dc5d86af7a1c1b58f',
    ),
    _GenreItem(
      title: 'Telugu',
      color: Color(0xFFD84000),
      endColor: Color(0xFFB03300),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf80699a8b7d59a21b38f964bd',
    ),
    _GenreItem(
      title: 'Charts',
      color: Color(0xFF8D67AB),
      endColor: Color(0xFF6B4B85),
      imageUrl:
          'https://charts-images.scdn.co/assets/locale_en/regional/weekly/region_global_default.jpg',
    ),
    _GenreItem(
      title: 'New Releases',
      color: Color(0xFF608108),
      endColor: Color(0xFF486105),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf194fec0fdc197fb9e4fe8e64',
    ),
    _GenreItem(
      title: 'Pop',
      color: Color(0xFF148A08),
      endColor: Color(0xFF0D6305),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf66d545e6a69d0bfe8bd1e825',
    ),
    _GenreItem(
      title: 'Hip-Hop',
      color: Color(0xFFBC5900),
      endColor: Color(0xFF944500),
      imageUrl:
          'https://i.scdn.co/image/ab676d630000e1f065710a92b40492f6e3dbb819',
    ),
    _GenreItem(
      title: 'Indie',
      color: Color(0xFFE91429),
      endColor: Color(0xFFB80D1D),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005cafa1a252e3a815b65778d8c2aa',
    ),
    _GenreItem(
      title: 'Love',
      color: Color(0xFFDC148C),
      endColor: Color(0xFFAF0E6E),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf21c9a95a2702ce535fb07915',
    ),
    _GenreItem(
      title: 'Party',
      color: Color(0xFF8D67AB),
      endColor: Color(0xFF6D4D87),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf0b0d0bfac454671832311615',
    ),
    _GenreItem(
      title: 'Devotional',
      color: Color(0xFFC39687),
      endColor: Color(0xFFA17769),
      imageUrl:
          'https://t.scdn.co/images/ad3e3f8f80eb494d998a435f7a5ae8c7',
    ),
    _GenreItem(
      title: 'Workout',
      color: Color(0xFF777777),
      endColor: Color(0xFF555555),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf6af6d83c78493644c9b0627b',
    ),
    _GenreItem(
      title: 'Chill',
      color: Color(0xFFB06239),
      endColor: Color(0xFF8A4B29),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf330ca3a3bfaf8b18407fb33e',
    ),
    _GenreItem(
      title: 'Gaming',
      color: Color(0xFFE8115B),
      endColor: Color(0xFFB50B44),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf26dd3719e8824756914ae61f',
    ),
    _GenreItem(
      title: 'Rock',
      color: Color(0xFF006450),
      endColor: Color(0xFF004739),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005cafda4c849095796a9e5d2c4ddb',
    ),
    _GenreItem(
      title: 'Classical',
      color: Color(0xFF7D4B32),
      endColor: Color(0xFF5E3622),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf3a3e91f32b562c1c85af3288',
    ),
    _GenreItem(
      title: 'Sleep',
      color: Color(0xFF1E3264),
      endColor: Color(0xFF132247),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf1cef0cee1e498abb8e74955f',
    ),
    _GenreItem(
      title: 'Dance/Electronic',
      color: Color(0xFF477D95),
      endColor: Color(0xFF335C6E),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf26ada793217994216c79dad8',
    ),
    _GenreItem(
      title: 'K-pop',
      color: Color(0xFFE61E32),
      endColor: Color(0xFFB81223),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf4b42030ee01cf793663dbb73',
    ),
    _GenreItem(
      title: 'Malayalam',
      color: Color(0xFF477D95),
      endColor: Color(0xFF31586B),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005caf77a5fdbc439492d09d3d84fb',
    ),
    _GenreItem(
      title: 'Bhojpuri',
      color: Color(0xFFE13300),
      endColor: Color(0xFFB02600),
      imageUrl:
          'https://i.scdn.co/image/ab67fb8200005cafe362fbcb5932b28679cf00f8',
    ),
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
            mainAxisExtent: 104,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final item = _genres[index];
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [item.color, item.endColor],
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onTap(item.title),
                  child: Stack(
                    children: [
                      // Tilted Cover Picture in bottom-right corner with realistic shadow
                      Positioned(
                        right: -16,
                        bottom: -4,
                        child: Transform.rotate(
                          angle: 0.44, // ~25 degrees tilt
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 10,
                                  offset: Offset(2, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: item.imageUrl,
                                fit: BoxFit.cover,
                                fadeInDuration:
                                    const Duration(milliseconds: 250),
                                errorWidget: (_, __, ___) => const ColoredBox(
                                  color: Colors.black26,
                                  child: Icon(
                                    Icons.music_note,
                                    color: Colors.white38,
                                    size: 28,
                                  ),
                                ),
                                placeholder: (_, __) => const ColoredBox(
                                  color: Colors.black12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Genre title in top-left
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 56, 12),
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
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
