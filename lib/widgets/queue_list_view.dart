import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/widgets/confirmation_dialog.dart';
import 'package:vybe/widgets/no_artwork_cube.dart';

class QueueWidget extends StatefulWidget {
  const QueueWidget({super.key, this.isBottomSheet = false});

  final bool isBottomSheet;

  @override
  State<QueueWidget> createState() => _QueueWidgetState();
}

class _QueueWidgetState extends State<QueueWidget> {
  List<Map> _queue = [];
  late StreamSubscription<List<Map>> _subscription;
  late StreamSubscription<MediaItem?> _mediaSubscription;
  bool _isDismissing = false;
  bool _hasScrolledToInitial = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _subscription = audioHandler.queueAsMapStream.listen((queue) {
      if (mounted && !_isDismissing) {
        setState(() {
          _queue = List<Map>.from(queue);
        });
        if (!_hasScrolledToInitial && queue.isNotEmpty) {
          _hasScrolledToInitial = true;
          _scrollToCurrentSong();
        }
      }
    });
    // listen to mediaItem changes UI reflects current song accurately.
    _mediaSubscription = audioHandler.mediaItem
        .distinct((prev, next) => prev?.id == next?.id)
        .listen((_) {
          if (mounted && !_isDismissing) setState(() {});
        });
  }

  void _scrollToCurrentSong() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final currentIndex = audioHandler.currentQueueIndex;
      if (currentIndex <= 0) return;
      const estimatedItemHeight = 68.0;
      const topPadding = 4.0;
      final targetOffset = currentIndex * estimatedItemHeight + topPadding;
      final clampedOffset = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _mediaSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currentIndex = audioHandler.currentQueueIndex;

    if (widget.isBottomSheet) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, colorScheme, textTheme, compact: true),
          _buildBottomSheetContent(context, colorScheme, currentIndex),
        ],
      );
    }

    return Column(
      children: [
        _buildHeader(context, colorScheme, textTheme, compact: false),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          indent: 8,
          endIndent: 8,
        ),
        Expanded(
          child: _queue.isEmpty
              ? _buildEmptyState(context, colorScheme, textTheme)
              : _buildList(context, colorScheme, currentIndex),
        ),
      ],
    );
  }

  Future<void> _shuffleQueue() async {
    await audioHandler.shuffleQueue();
    if (mounted && _scrollController.hasClients) {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _confirmClearQueue(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => ConfirmationDialog(
        confirmationMessage: context.l10n!.clearQueueQuestion,
        submitMessage: context.l10n!.clear,
        isDangerous: true,
        onCancel: () => Navigator.pop(context),
        onSubmit: () {
          Navigator.pop(context);
          audioHandler.clearQueue();
          if (widget.isBottomSheet) Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required bool compact,
  }) {
    return Padding(
      padding: compact
          ? const EdgeInsets.only(left: 10, right: 8, bottom: 12)
          : const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 8 : 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              FluentIcons.apps_list_24_regular,
              color: colorScheme.onPrimaryContainer,
              size: compact ? 20.0 : 22.0,
            ),
          ),
          SizedBox(width: compact ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n!.queue,
                  style: compact
                      ? TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        )
                      : textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                ),
                if (_queue.isNotEmpty)
                  Text(
                    '${_queue.length} ${context.l10n!.songs.toLowerCase()}',
                    style: compact
                        ? TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          )
                        : textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
              ],
            ),
          ),
          if (_queue.length > 1)
            IconButton.filledTonal(
              onPressed: _shuffleQueue,
              icon: const Icon(FluentIcons.arrow_shuffle_24_filled, size: 18),
              tooltip: context.l10n!.shuffle,
              visualDensity: VisualDensity.compact,
            ),
          if (_queue.isNotEmpty) ...[
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () => _confirmClearQueue(context),
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
              label: Text(context.l10n!.clear),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomSheetContent(
    BuildContext context,
    ColorScheme colorScheme,
    int currentIndex,
  ) {
    if (_queue.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          context.l10n!.noSongsInQueue,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
        ),
      );
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.52,
      child: _buildList(context, colorScheme, currentIndex, closeOnTap: true),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                FluentIcons.music_note_1_24_regular,
                color: colorScheme.onSurfaceVariant,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n!.noSongsInQueue,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _queueEntryKey(Map song, int index) {
    final entryId = song['queueEntryId']?.toString() ?? song['ytid'];
    return '${entryId}_$index';
  }

  Widget _buildList(
    BuildContext context,
    ColorScheme colorScheme,
    int currentIndex, {
    bool closeOnTap = false,
  }) {
    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(top: 4, bottom: 24, left: 8, right: 8),
      footer: AutoplaySuggestions(
        // Reload when the song changes or the queue grows or shrinks, since
        // queued songs are left out of the suggestions.
        key: ValueKey(
          '${audioHandler.mediaItem.value?.id}_${_queue.length}',
        ),
        closeOnTap: closeOnTap,
      ),
      itemCount: _queue.length,
      onReorderItem: (oldIndex, newIndex) {
        final movingId =
            _queue[oldIndex]['queueEntryId']?.toString() ??
            'legacy_${_queue[oldIndex]['ytid']}_$oldIndex';

        setState(() {
          final item = _queue.removeAt(oldIndex);
          var insertIndex = newIndex;
          if (insertIndex < 0) insertIndex = 0;
          if (insertIndex > _queue.length) insertIndex = _queue.length;
          _queue.insert(insertIndex, item);
        });

        final actualIndex = _queue.indexWhere(
          (item) => item['queueEntryId']?.toString() == movingId,
        );
        audioHandler.reorderQueueById(movingId, actualIndex);
      },
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        shadowColor: colorScheme.shadow.withValues(alpha: 0.35),
        child: child,
      ),
      itemBuilder: (context, index) {
        final song = _queue[index];
        final isCurrentSong = index == currentIndex;
        final queueEntryId = _queueEntryKey(song, index);
        return QueueTile(
          key: ValueKey(queueEntryId),
          song: song,
          index: index,
          queueEntryId: queueEntryId,
          isCurrentSong: isCurrentSong,
          colorScheme: colorScheme,
          onTap: () {
            audioHandler.skipToSong(index);
            if (closeOnTap) Navigator.pop(context);
          },
          confirmDismiss: (_) async {
            _isDismissing = true;
            return true;
          },
          onDismissed: () {
            final actualIndex = _queue.indexWhere(
              (item) =>
                  _queueEntryKey(item, _queue.indexOf(item)) == queueEntryId,
            );
            if (actualIndex == -1) return;
            setState(() {
              _isDismissing = false;
              _queue.removeAt(actualIndex);
            });
            audioHandler.removeFromQueue(actualIndex);
          },
        );
      },
    );
  }
}

class QueueTile extends StatelessWidget {
  const QueueTile({
    super.key,
    required this.song,
    required this.index,
    required this.queueEntryId,
    required this.isCurrentSong,
    required this.colorScheme,
    required this.onTap,
    required this.onDismissed,
    this.confirmDismiss,
  });

  final Map song;
  final int index;
  final String queueEntryId;
  final bool isCurrentSong;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback onDismissed;
  final Future<bool?> Function(DismissDirection)? confirmDismiss;

  static const double _artSize = 46;
  static const double _artRadius = 10;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(queueEntryId),
      confirmDismiss: confirmDismiss,
      onDismissed: (_) => onDismissed(),
      background: _DismissBackground(
        alignment: Alignment.centerLeft,
        colorScheme: colorScheme,
      ),
      secondaryBackground: _DismissBackground(
        alignment: Alignment.centerRight,
        colorScheme: colorScheme,
      ),
      child: Material(
        color: isCurrentSong
            ? colorScheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.transparent,
          highlightColor: colorScheme.onSurface.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _ArtworkThumbnail(
                  song: song,
                  size: _artSize,
                  radius: _artRadius,
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song['title']?.toString() ?? '',
                        style: TextStyle(
                          color: isCurrentSong
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: isCurrentSong
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song['artist']?.toString() ?? '',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isCurrentSong) ...[
                  Icon(
                    FluentIcons.music_note_2_24_regular,
                    color: colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                ],
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 14,
                    ),
                    child: Icon(
                      FluentIcons.re_order_24_regular,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Songs similar to the current one that autoplay will play once the queue
/// ends, shown under the queue with a switch to turn autoplay on or off.
class AutoplaySuggestions extends StatefulWidget {
  const AutoplaySuggestions({super.key, this.closeOnTap = false});

  final bool closeOnTap;

  @override
  State<AutoplaySuggestions> createState() => _AutoplaySuggestionsState();
}

class _AutoplaySuggestionsState extends State<AutoplaySuggestions> {
  Future<List<Map>>? _suggestions;

  @override
  void initState() {
    super.initState();
    playNextSongAutomatically.addListener(_reload);
    offlineMode.addListener(_reload);
    _suggestions = _load();
  }

  @override
  void dispose() {
    playNextSongAutomatically.removeListener(_reload);
    offlineMode.removeListener(_reload);
    super.dispose();
  }

  Future<List<Map>>? _load() =>
      playNextSongAutomatically.value && !offlineMode.value
      ? audioHandler.upcomingSuggestions()
      : null;

  void _reload() {
    if (mounted) setState(() => _suggestions = _load());
  }

  void _setAutoplay(bool value) {
    playNextSongAutomatically.value = value;
    addOrUpdateData<bool>('settings', 'playNextSongAutomatically', value);
  }

  @override
  Widget build(BuildContext context) {
    if (offlineMode.value || audioHandler.mediaItem.value == null) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n!;
    final enabled = playNextSongAutomatically.value;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.autoplaySimilarSongs,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? l10n.autoplaySimilarSongsHint
                            : l10n.autoplayTurnOnHint,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: enabled, onChanged: _setAutoplay),
              ],
            ),
          ),
          if (enabled)
            FutureBuilder<List<Map>>(
              future: _suggestions,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Column(
                    children: List.generate(
                      3,
                      (_) => _SuggestionPlaceholder(colorScheme: colorScheme),
                    ),
                  );
                }
                final songs = snapshot.data ?? const [];
                return Column(
                  children: [
                    for (final song in songs)
                      _SuggestionTile(
                        song: song,
                        colorScheme: colorScheme,
                        onTap: () {
                          audioHandler.playSuggestion(song);
                          if (widget.closeOnTap) Navigator.pop(context);
                        },
                        onAdd: () {
                          audioHandler.addToQueue(song);
                          showToast(context, l10n.addedToQueue);
                        },
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.song,
    required this.colorScheme,
    required this.onTap,
    required this.onAdd,
  });

  final Map song;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
        child: Row(
          children: [
            _ArtworkThumbnail(
              song: song,
              size: QueueTile._artSize,
              radius: QueueTile._artRadius,
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song['title']?.toString() ?? '',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song['artist']?.toString() ?? '',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onAdd,
              tooltip: context.l10n!.addToQueue,
              icon: Icon(
                FluentIcons.add_circle_24_regular,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionPlaceholder extends StatelessWidget {
  const _SuggestionPlaceholder({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final fill = colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: QueueTile._artSize,
            height: QueueTile._artSize,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(QueueTile._artRadius),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [bar(150, 12), const SizedBox(height: 6), bar(90, 10)],
          ),
        ],
      ),
    );
  }
}

class _ArtworkThumbnail extends StatelessWidget {
  const _ArtworkThumbnail({
    required this.song,
    required this.size,
    required this.radius,
    required this.colorScheme,
  });

  final Map song;
  final double size;
  final double radius;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final artworkPath = song['artworkPath'] as String?;
    if (artworkPath != null && artworkPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(artworkPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    final imageUrl = song['lowResImage']?.toString() ?? '';
    if (imageUrl.isEmpty) return _fallback();
    // Low-res YouTube 'default.jpg' thumbnails ship with baked-in black
    // letterbox bars, so BoxFit.cover keeps them visible. Detect that case and
    // stretch over the bars with fill + centerSlice, otherwise crop with cover —
    // matching SongBar so the queue frames covers the same way (no black bars).
    final isImageSmall = imageUrl.contains('default.jpg');
    return CachedNetworkImage(
      width: size,
      height: size,
      imageUrl: imageUrl,
      imageBuilder: (_, imageProvider) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image(
          image: imageProvider,
          width: size,
          height: size,
          fit: isImageSmall ? BoxFit.fill : BoxFit.cover,
          centerSlice: isImageSmall ? const Rect.fromLTRB(1, 1, 1, 1) : null,
        ),
      ),
      placeholder: (_, __) => _loading(),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() => NullArtworkWidget(
    size: size,
    borderRadius: radius,
    iconSize: size * 0.45,
  );

  Widget _loading() => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground({
    required this.alignment,
    required this.colorScheme,
  });

  final Alignment alignment;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        FluentIcons.delete_24_regular,
        color: colorScheme.onErrorContainer,
        size: 22,
      ),
    );
  }
}
