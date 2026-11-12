import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';

/// The metadata below a playlist, album or artist hero, laid out the way
/// Spotify does: a single grey subtitle line, left aligned.
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    super.key,
    required this.title,
    this.songsLength,
    this.isAlbum,
    this.isArtist = false,
    this.showTitle = true,
    this.monthlyListeners,
    this.description,
  });

  final String title;

  /// Left null by the artist page, which does not hold the song list itself.
  final int? songsLength;
  final bool? isAlbum;
  final bool isArtist;
  final bool showTitle;

  /// Monthly listeners of an artist, already shortened, e.g. `447M`.
  final String? monthlyListeners;

  /// Artist biography, collapsed until tapped.
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final parts = <String>[
      if (isArtist)
        context.l10n!.artist
      else if (isAlbum == true)
        context.l10n!.album
      else if (isAlbum == false)
        context.l10n!.playlist,
      if (songsLength == 1 &&
          Localizations.localeOf(context).languageCode == 'en')
        '1 song'
      else if (songsLength != null)
        '$songsLength ${context.l10n!.songs}',
      if (monthlyListeners != null)
        '$monthlyListeners ${context.l10n!.monthlyListeners}',
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(0, showTitle ? 20 : 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle) ...[
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.secondary,
                letterSpacing: 0,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: 6),
          ],
          if (parts.isNotEmpty)
            Text(
              parts.join(' \u2022 '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (description != null && description!.trim().isNotEmpty)
            _Description(description!.trim()),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// The artist biography, three lines until it is tapped.
class _Description extends StatefulWidget {
  const _Description(this.text);

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GestureDetector(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Text(
          widget.text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
          maxLines: _isExpanded ? null : 3,
          overflow: _isExpanded ? TextOverflow.clip : TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
