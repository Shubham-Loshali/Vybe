import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/services/update_manager.dart';
import 'package:vybe/utilities/flutter_bottom_sheet.dart'
    show closeCurrentBottomSheet;
import 'package:vybe/utilities/url_launcher.dart';
import 'package:vybe/widgets/mini_player.dart';
import 'package:vybe/widgets/spotify_header.dart';

class BottomNavigationPage extends StatefulWidget {
  const BottomNavigationPage({required this.child, super.key});

  final StatefulNavigationShell child;

  @override
  State<BottomNavigationPage> createState() => _BottomNavigationPageState();
}

class _BottomNavigationPageState extends State<BottomNavigationPage> {
  late final _miniPlayerVisibilityStream = audioHandler.mediaItem
      .map((mediaItem) => mediaItem != null)
      .distinct();

  bool? _previousOfflineMode;

  /// Track the previously selected shell branch to detect reselects.
  int? _previousShellIndex;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isAppBlockedByUpdate,
      builder: (context, isBlocked, _) {
        if (isBlocked) {
          return const _ForceUpdateBlockingScreen();
        }

        return PopScope(
          canPop: widget.child.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        final currentIndex = widget.child.currentIndex;
        if (currentIndex != 0) {
          widget.child.goBranch(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: offlineMode,
        builder: (context, isOfflineMode, _) {
          if (_previousOfflineMode != null &&
              _previousOfflineMode != isOfflineMode) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              _handleOfflineModeChange(isOfflineMode);
            });
          }
          _previousOfflineMode = isOfflineMode;

          return LayoutBuilder(
            builder: (context, constraints) {
              final isLargeScreen = MediaQuery.of(context).size.width >= 600;
              final items = _getNavigationItems(isOfflineMode);

              return Scaffold(
                body: SafeArea(
                  child: Row(
                    children: [
                      if (isLargeScreen)
                        NavigationRail(
                          labelType: NavigationRailLabelType.selected,
                          destinations: items
                              .map(
                                (item) => NavigationRailDestination(
                                  icon: Icon(item.icon),
                                  selectedIcon: Icon(item.selectedIcon),
                                  label: Text(item.label),
                                ),
                              )
                              .toList(),
                          selectedIndex: _getCurrentIndex(items),
                          onDestinationSelected: (index) =>
                              _onTabTapped(index, items),
                        ),
                      Expanded(
                        child: StreamBuilder<bool>(
                          initialData: audioHandler.mediaItem.value != null,
                          stream: _miniPlayerVisibilityStream,
                          builder: (context, snapshot) {
                            final mediaQuery = MediaQuery.of(context);
                            final isMiniPlayerVisible = snapshot.data ?? false;
                            final bottomPadding = !isMiniPlayerVisible
                                ? mediaQuery.padding.bottom
                                : mediaQuery.padding.bottom +
                                      miniPlayerTotalHeight;

                            return Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                MediaQuery(
                                  data: mediaQuery.copyWith(
                                    padding: mediaQuery.padding.copyWith(
                                      bottom: bottomPadding,
                                    ),
                                  ),
                                  child: widget.child,
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  child: MiniPlayer(),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: !isLargeScreen
                    ? DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xE6121212), Color(0xFF000000)],
                          ),
                        ),
                        child: NavigationBar(
                        backgroundColor: Colors.transparent,
                        selectedIndex: _getCurrentIndex(items),
                        labelBehavior:
                            NavigationDestinationLabelBehavior.alwaysShow,
                        onDestinationSelected: (index) =>
                            _onTabTapped(index, items),
                        destinations: items
                            .map(
                              (item) => NavigationDestination(
                                icon: Icon(item.icon),
                                selectedIcon: Icon(item.selectedIcon),
                                label: item.label,
                              ),
                            )
                            .toList(),
                      ),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
      },
    );
  }

  List<_NavigationItem> _getNavigationItems(bool isOfflineMode) {
    final items = <_NavigationItem>[
      _NavigationItem(
        icon: FluentIcons.home_24_regular,
        selectedIcon: FluentIcons.home_24_filled,
        label: context.l10n?.home ?? 'Home',
        shellIndex: 0,
      ),
    ];

    // Only add search tab in online mode
    if (!isOfflineMode) {
      items.add(
        _NavigationItem(
          icon: FluentIcons.search_24_regular,
          selectedIcon: FluentIcons.search_24_filled,
          label: context.l10n?.search ?? 'Search',
          shellIndex: 1,
        ),
      );
    }

    items.add(
      _NavigationItem(
        icon: FluentIcons.library_24_regular,
        selectedIcon: FluentIcons.library_24_filled,
        label: yourLibraryLabel(context.l10n?.library ?? 'Library'),
        shellIndex: 2,
      ),
    );
    if (!isOfflineMode) {
      items.add(
        _NavigationItem(
          icon: FluentIcons.arrow_download_24_regular,
          selectedIcon: FluentIcons.arrow_download_24_filled,
          label: context.l10n?.importTab ?? 'Import',
          shellIndex: NavigationManager.importBranchIndex,
        ),
      );
    }

    return items;
  }

  void _handleOfflineModeChange(bool isOfflineMode) {
    if (!mounted) return;

    final currentRoute = GoRouterState.of(context).matchedLocation;

    if (isOfflineMode &&
        (currentRoute.startsWith(NavigationManager.searchPath) ||
            currentRoute == NavigationManager.importPath)) {
      widget.child.goBranch(0);
    }
  }

  void _onTabTapped(int index, List<_NavigationItem> items) {
    if (index < items.length) {
      final item = items[index];
      final isReselect = _previousShellIndex == item.shellIndex;

      // Close any open bottom sheet before switching tabs
      closeCurrentBottomSheet();

      // If user taps the same tab again, reset it to initial state.
      // Otherwise, preserve the branch state.
      if (isReselect) {
        widget.child.goBranch(item.shellIndex, initialLocation: true);
      } else {
        widget.child.goBranch(item.shellIndex);
      }

      _previousShellIndex = item.shellIndex;
    }
  }

  int _getCurrentIndex(List<_NavigationItem> items) {
    final currentShellIndex = widget.child.currentIndex;

    if (items.isEmpty) return 0;

    // Try to find the current shell index in the available items
    final matchedIndex = items.indexWhere(
      (item) => item.shellIndex == currentShellIndex,
    );
    if (matchedIndex != -1) return matchedIndex;

    // Fall back to Home when the active branch has no visible tab.
    return 0;
  }
}

class _NavigationItem {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.shellIndex,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int shellIndex;
}

class _ForceUpdateBlockingScreen extends StatelessWidget {
  const _ForceUpdateBlockingScreen();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE91E63).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      FluentIcons.arrow_download_24_filled,
                      color: Color(0xFFE91E63),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Update Required',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This version of Vybe has been shut down and is no longer operational.\n\nYou must update to the latest version to continue using the app.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFFB3B3B3),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        launchURL(
                          Uri.parse(
                            'https://github.com/Shubham-Loshali/Vybe/releases/latest',
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      icon: const Icon(FluentIcons.arrow_download_20_filled),
                      label: const Text('Update Vybe Now'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: SystemNavigator.pop,
                    child: const Text(
                      'Exit App',
                      style: TextStyle(
                        color: Color(0xFFB3B3B3),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
