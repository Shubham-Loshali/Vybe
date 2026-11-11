import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/utilities/mediaitem.dart';

class SpotifyLikeButton extends StatefulWidget {
  const SpotifyLikeButton({
    super.key,
    required this.metadata,
    this.size = 26.0,
  });

  final MediaItem metadata;
  final double size;

  @override
  State<SpotifyLikeButton> createState() => _SpotifyLikeButtonState();
}

class _SpotifyLikeButtonState extends State<SpotifyLikeButton>
    with SingleTickerProviderStateMixin {
  late final ValueNotifier<bool> _isLikedNotifier;
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;

  String? get _audioId => widget.metadata.extras?['ytid']?.toString();
  bool get _isRadioStation => widget.metadata.extras?['isLive'] == true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1), weight: 50),
    ]).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    final initialLiked = _computeLiked();
    _isLikedNotifier = ValueNotifier<bool>(initialLiked);

    if (_isRadioStation) {
      userLikedRadioStations.addListener(_syncStatus);
    } else {
      userLikedSongsList.addListener(_syncStatus);
    }
  }

  bool _computeLiked() {
    final id = _audioId;
    if (id == null || id.isEmpty) return false;
    return _isRadioStation
        ? isRadioStationLiked(id)
        : isSongAlreadyLiked(id);
  }

  void _syncStatus() {
    final current = _computeLiked();
    if (_isLikedNotifier.value != current) {
      _isLikedNotifier.value = current;
    }
  }

  @override
  void didUpdateWidget(SpotifyLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.metadata.extras?['ytid']?.toString();
    final oldIsRadio = oldWidget.metadata.extras?['isLive'] == true;

    if (oldIsRadio != _isRadioStation) {
      if (oldIsRadio) {
        userLikedRadioStations.removeListener(_syncStatus);
      } else {
        userLikedSongsList.removeListener(_syncStatus);
      }
      if (_isRadioStation) {
        userLikedRadioStations.addListener(_syncStatus);
      } else {
        userLikedSongsList.addListener(_syncStatus);
      }
    }

    if (oldId != _audioId || oldIsRadio != _isRadioStation) {
      _isLikedNotifier.value = _computeLiked();
    }
  }

  @override
  void dispose() {
    if (_isRadioStation) {
      userLikedRadioStations.removeListener(_syncStatus);
    } else {
      userLikedSongsList.removeListener(_syncStatus);
    }
    _isLikedNotifier.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final id = _audioId;
    if (id == null || id.isEmpty) return;

    final wasLiked = _isLikedNotifier.value;
    final nextState = !wasLiked;
    _isLikedNotifier.value = nextState;

    if (nextState) {
      unawaited(_animController.forward(from: 0));
    }

    try {
      if (_isRadioStation) {
        if (wasLiked) {
          await removeRadioStationFromLiked(id);
        } else {
          await addRadioStationToLiked(id);
        }
      } else {
        await updateSongLikeStatus(
          id,
          nextState,
          songData: mediaItemToMap(widget.metadata),
        );
      }
    } catch (e) {
      _isLikedNotifier.value = wasLiked;
      logger.log('Error toggling SpotifyLikeButton', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isLikedNotifier,
      builder: (context, isLiked, _) {
        return ScaleTransition(
          scale: _scaleAnimation,
          child: IconButton(
            iconSize: widget.size,
            padding: const EdgeInsets.all(8),
            constraints: BoxConstraints(
              minWidth: widget.size + 16,
              minHeight: widget.size + 16,
            ),
            icon: Icon(
              isLiked
                  ? FluentIcons.heart_24_filled
                  : FluentIcons.heart_24_regular,
              color: isLiked ? const Color(0xFF1DB954) : Colors.white70,
            ),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onPressed: _toggleLike,
          ),
        );
      },
    );
  }
}

