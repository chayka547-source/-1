import 'package:flutter/material.dart';

import 'home_page.dart';
import 'import_page.dart';
import 'library_page.dart';
import 'mini_player.dart';
import 'search_page.dart';
import 'widgets.dart';

/// Главный экран: четыре вкладки, мини-плеер и нижнее меню.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _pages = <Widget>[
    HomePage(),
    SearchPage(),
    LibraryPage(),
    ImportPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tabIndex,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(index: index, children: _pages),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => tabIndex.value = i,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Главная',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Поиск',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: 'Медиатека',
                ),
                NavigationDestination(
                  icon: Icon(Icons.swap_horiz),
                  label: 'Импорт',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
