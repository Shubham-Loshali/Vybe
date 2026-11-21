import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/followed_artists_service.dart';

/// A Spotify-inspired Follow / Following button for artist & singer profile pages.
class ArtistFollowButton extends StatelessWidget {
  const ArtistFollowButton({
    super.key,
    required this.artistData,
    this.compact = false,
  });

  final Map<dynamic, dynamic> artistData;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final artistId = (artistData['ytid'] ?? artistData['id'])?.toString();
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: FollowedArtistsService.instance.followedArtists,
      builder: (context, _, __) {
        final isFollowing = FollowedArtistsService.instance.isFollowing(artistId);

        if (compact) {
          return IconButton(
            icon: Icon(
              isFollowing
                  ? FluentIcons.person_star_24_filled
                  : FluentIcons.person_add_24_regular,
              color: isFollowing ? const Color(0xFF1DB954) : colorScheme.onSurface,
            ),
            tooltip: isFollowing ? 'Following' : 'Follow',
            onPressed: () => FollowedArtistsService.instance.toggleFollow(
              artistData,
              context: context,
            ),
          );
        }

        // Spotify pill button style
        return OutlinedButton.icon(
          onPressed: () => FollowedArtistsService.instance.toggleFollow(
            artistData,
            context: context,
          ),
          icon: Icon(
            isFollowing
                ? FluentIcons.checkmark_16_filled
                : FluentIcons.add_16_regular,
            size: 16,
            color: isFollowing ? const Color(0xFF1DB954) : Colors.white,
          ),
          label: Text(
            isFollowing ? 'Following' : 'Follow',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: isFollowing ? const Color(0xFF1DB954) : Colors.white,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            side: BorderSide(
              color: isFollowing
                  ? const Color(0xFF1DB954)
                  : Colors.white.withValues(alpha: 0.35),
              width: 1.2,
            ),
            backgroundColor: isFollowing
                ? const Color(0xFF1DB954).withValues(alpha: 0.12)
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        );
      },
    );
  }
}
