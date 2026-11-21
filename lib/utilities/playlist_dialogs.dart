import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/services/collaborative_playlist_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/utilities/collaborative_playlist_dialogs.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/utilities/playlist_image_picker.dart';
import 'package:vybe/widgets/dialog_item.dart';

void showCreatePlaylistDialog(
  BuildContext context, {
  dynamic songToAdd,
  List<dynamic>? songsToAdd,
}) {
  final parentContext = context;
  var id = '';
  var customPlaylistName = '';
  var isYouTubeMode = songToAdd == null && songsToAdd == null;
  var isCollaborative = false;
  var isSubmitting = false;
  String? imageUrl;
  String? imageBase64;

  showDialog(
    context: parentContext,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, dialogSetState) {
          final colorScheme = Theme.of(context).colorScheme;

          Future<void> _pickImage() async {
            final result = await pickImage();
            if (result != null) {
              dialogSetState(() {
                imageBase64 = result;
                imageUrl = null;
              });
            }
          }

          Widget _imagePreview() {
            return buildImagePreview(
              imageBase64: imageBase64,
              imageUrl: imageUrl,
            );
          }

          return AlertDialog(
            icon: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                FluentIcons.add_24_filled,
                color: colorScheme.primary,
                size: 32,
              ),
            ),
            title: Text(
              context.l10n!.addPlaylist,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            titleTextStyle: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (songToAdd == null && songsToAdd == null)
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                dialogSetState(() {
                                  isYouTubeMode = true;
                                  id = '';
                                  customPlaylistName = '';
                                  imageUrl = null;
                                  imageBase64 = null;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isYouTubeMode
                                      ? colorScheme.primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      FluentIcons.globe_20_filled,
                                      size: 20,
                                      color: isYouTubeMode
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'YouTube',
                                      style: TextStyle(
                                        color: isYouTubeMode
                                            ? colorScheme.onPrimaryContainer
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight: isYouTubeMode
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                dialogSetState(() {
                                  isYouTubeMode = false;
                                  id = '';
                                  customPlaylistName = '';
                                  imageUrl = null;
                                  imageBase64 = null;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: !isYouTubeMode
                                      ? colorScheme.primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      FluentIcons.person_20_filled,
                                      size: 20,
                                      color: !isYouTubeMode
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      context.l10n!.custom,
                                      style: TextStyle(
                                        color: !isYouTubeMode
                                            ? colorScheme.onPrimaryContainer
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight: !isYouTubeMode
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (isYouTubeMode)
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.l10n!.youtubePlaylistLinkOrId,
                        prefixIcon: Icon(
                          FluentIcons.link_20_regular,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                      ),
                      onChanged: (value) {
                        id = value;
                      },
                    )
                  else ...[
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.l10n!.customPlaylistName,
                        prefixIcon: Icon(
                          FluentIcons.text_field_20_regular,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                      ),
                      autofocus: true,
                      onChanged: (value) {
                        customPlaylistName = value;
                      },
                    ),
                    if (imageBase64 == null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          labelText: context.l10n!.customPlaylistImgUrl,
                          prefixIcon: Icon(
                            FluentIcons.image_20_regular,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                        ),
                        onChanged: (value) {
                          imageUrl = value;
                          imageBase64 = null;
                          dialogSetState(() {});
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (imageUrl == null) ...[
                      buildImagePickerRow(
                        context,
                        _pickImage,
                        imageBase64 != null,
                      ),
                      _imagePreview(),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isCollaborative,
                      activeThumbColor: const Color(0xFF1DB954),
                      title: const Text(
                        'Collaborative Playlist',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Invite friends to add & edit songs together',
                        style: TextStyle(fontSize: 12),
                      ),
                      secondary: Icon(
                        FluentIcons.people_team_20_filled,
                        color: isCollaborative
                            ? const Color(0xFF1DB954)
                            : colorScheme.onSurfaceVariant,
                      ),
                      onChanged: (value) {
                        dialogSetState(() {
                          isCollaborative = value;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: <Widget>[
              OutlinedButton(
                onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(context.l10n!.cancel),
              ),
              FilledButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (isYouTubeMode && id.trim().isNotEmpty) {
                          final ytId = id.trim();
                          isSubmitting = true;
                          dialogSetState(() {});
                          Navigator.of(dialogContext).pop();

                          final result = await addUserPlaylist(ytId, parentContext);
                          showToast(NavigationManager().context, result);
                        } else if (!isYouTubeMode &&
                            customPlaylistName.trim().isNotEmpty) {
                          final cleanName = customPlaylistName.trim();
                          final alreadyExists = userCustomPlaylists.value.any(
                            (p) =>
                                (p['title'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase() ==
                                cleanName.toLowerCase(),
                          );
                          if (alreadyExists) {
                            showToast(
                              dialogContext,
                              'Playlist "$cleanName" already exists',
                            );
                            return;
                          }

                          isSubmitting = true;
                          dialogSetState(() {});
                          Navigator.of(dialogContext).pop();

                          if (isCollaborative) {
                            final collabResult =
                                await CollaborativePlaylistService.instance
                                    .createCollaborativePlaylist(
                              cleanName,
                              image: imageBase64 ?? imageUrl,
                              context: parentContext,
                            );
                            final newPlaylistId =
                                collabResult.playlistId ?? '';

                            if (songToAdd != null &&
                                newPlaylistId.isNotEmpty) {
                              final addResult = addSongInCustomPlaylist(
                                NavigationManager().context,
                                newPlaylistId,
                                songToAdd,
                              );
                              showToast(
                                NavigationManager().context,
                                addResult,
                              );
                            } else if (songsToAdd != null &&
                                songsToAdd.isNotEmpty &&
                                newPlaylistId.isNotEmpty) {
                              final addResult = addSongsInCustomPlaylist(
                                NavigationManager().context,
                                newPlaylistId,
                                songsToAdd,
                              );
                              showToast(
                                NavigationManager().context,
                                addResult,
                              );
                            } else {
                              showToast(
                                NavigationManager().context,
                                collabResult.message,
                              );
                            }

                            if (newPlaylistId.isNotEmpty) {
                              final matchIndex =
                                  userCustomPlaylists.value.indexWhere(
                                (p) =>
                                    (p['ytid'] ?? p['id'])?.toString() ==
                                    newPlaylistId,
                              );
                              final inviteCode = collabResult.inviteCode ?? '';
                              final created = matchIndex != -1
                                  ? Map<String, dynamic>.from(
                                      userCustomPlaylists.value[matchIndex])
                                  : <String, dynamic>{
                                      'ytid': newPlaylistId,
                                      'title': cleanName,
                                      'collabId': inviteCode,
                                      'inviteCode': inviteCode,
                                      'isCollaborative': true,
                                    };
                              created['collabId'] ??= inviteCode;
                              created['inviteCode'] ??= inviteCode;

                              if (parentContext.mounted) {
                                showCollaborativePlaylistShareDialog(
                                  parentContext,
                                  created,
                                );
                              }
                            }
                          } else {
                            final pair = createCustomPlaylist(
                              cleanName,
                              imageBase64 ?? imageUrl,
                              parentContext,
                            );
                            final newPlaylistId = pair.$2;

                            if (songToAdd != null &&
                                newPlaylistId.isNotEmpty) {
                              final addResult = addSongInCustomPlaylist(
                                NavigationManager().context,
                                newPlaylistId,
                                songToAdd,
                              );
                              showToast(
                                NavigationManager().context,
                                addResult,
                              );
                            } else if (songsToAdd != null &&
                                songsToAdd.isNotEmpty &&
                                newPlaylistId.isNotEmpty) {
                              final addResult = addSongsInCustomPlaylist(
                                NavigationManager().context,
                                newPlaylistId,
                                songsToAdd,
                              );
                              showToast(
                                NavigationManager().context,
                                addResult,
                              );
                            } else {
                              showToast(NavigationManager().context, pair.$1);
                            }
                          }
                        } else {
                          showToast(
                            dialogContext,
                            '${context.l10n!.provideIdOrNameError}.',
                          );
                        }
                      },
                icon: const Icon(FluentIcons.add_20_filled),
                label: Text(context.l10n!.add),
              ),
            ],
          );
        },
      );
    },
  );
}

void showAddToPlaylistDialog(
  BuildContext context, {
  dynamic song,
  List<dynamic>? songs,
}) {
  final parentContext = context;
  showDialog(
    context: parentContext,
    builder: (BuildContext dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            FluentIcons.album_add_24_filled,
            color: colorScheme.secondary,
            size: 28,
          ),
        ),
        title: Text(
          dialogContext.l10n!.addToPlaylist,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.6,
          ),
          child: Builder(
            builder: (context) {
              final folders = userPlaylistFolders.value
                  .where(
                    (folder) =>
                        folder['playlists'] != null &&
                        (folder['playlists'] as List).isNotEmpty,
                  )
                  .toList();
              final topLevelPlaylists = getPlaylistsNotInFolders();

              final hasAny =
                  (folders.isNotEmpty) || (topLevelPlaylists.isNotEmpty);

              if (!hasAny) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        dialogContext.l10n!.noCustomPlaylists,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              }

              return ListView.builder(
                itemCount: folders.length + topLevelPlaylists.length,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  if (index < folders.length) {
                    final folder = folders[index];

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ExpansionTile(
                        collapsedBackgroundColor:
                            colorScheme.surfaceContainerLow,
                        backgroundColor: colorScheme.surfaceContainerLowest,
                        shape: RoundedRectangleBorder(
                          borderRadius: commonBarRadius,
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: commonBarRadius,
                        ),
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            FluentIcons.folder_24_regular,
                            color: colorScheme.secondary,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          folder['name'] ?? '',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        children: [
                          for (final p in (folder['playlists'] as List? ?? []))
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 16,
                              ),
                              child: DialogItem(
                                icon: FluentIcons.text_bullet_list_24_filled,
                                iconColor: colorScheme.tertiary,
                                iconBgColor: colorScheme.tertiaryContainer,
                                label: p['title'] ?? '',
                                onTap: () {
                                  final targetId =
                                      (p['ytid'] ?? p['id'])?.toString() ?? '';
                                  Navigator.of(dialogContext).pop();
                                  if (song != null) {
                                    final res = addSongInCustomPlaylist(
                                      parentContext,
                                      targetId,
                                      song,
                                    );
                                    showToast(NavigationManager().context, res);
                                  } else if (songs != null &&
                                      songs.isNotEmpty) {
                                    final res = addSongsInCustomPlaylist(
                                      parentContext,
                                      targetId,
                                      songs,
                                    );
                                    showToast(NavigationManager().context, res);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  }

                  final playlistIndex = index - folders.length;
                  final playlist = topLevelPlaylists[playlistIndex];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: DialogItem(
                      icon: FluentIcons.text_bullet_list_24_filled,
                      iconColor: colorScheme.tertiary,
                      iconBgColor: colorScheme.tertiaryContainer,
                      label: playlist['title'] ?? '',
                      onTap: () {
                        final targetId =
                            (playlist['ytid'] ?? playlist['id'])?.toString() ??
                                '';
                        Navigator.of(dialogContext).pop();
                        if (song != null) {
                          final res = addSongInCustomPlaylist(
                            parentContext,
                            targetId,
                            song,
                          );
                          showToast(NavigationManager().context, res);
                        } else if (songs != null && songs.isNotEmpty) {
                          final res = addSongsInCustomPlaylist(
                            parentContext,
                            targetId,
                            songs,
                          );
                          showToast(NavigationManager().context, res);
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            child: Text(dialogContext.l10n!.cancel),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              showCreatePlaylistDialog(
                parentContext,
                songToAdd: song,
                songsToAdd: songs,
              );
            },
            icon: const Icon(FluentIcons.add_24_regular, size: 18),
            label: Text(dialogContext.l10n!.addPlaylist),
          ),
        ],
      );
    },
  );
}
