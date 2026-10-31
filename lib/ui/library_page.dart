import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'playlist_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// Медиатека: сохранённые треки, плейлисты и всё, что доступно без интернета.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  Future<void> _addFiles(BuildContext context) async {
    final app = context.read<AppState>();
    final n = await app.addLocalFiles();
    if (n > 0) app.say('Добавлено треков: $n');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Медиатека'),
          actions: [
            IconButton(
              tooltip: 'Добавить файлы с телефона',
              icon: const Icon(Icons.library_add_outlined),
              onPressed: () => _addFiles(context),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Треки'),
              Tab(text: 'Плейлисты'),
              Tab(text: 'Офлайн'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TrackListView(
              tracks: app.libraryTracks,
              empty: EmptyState(
                icon: Icons.library_music_outlined,
                text: 'Здесь будут ваши треки. Добавьте музыкальные файлы '
                    'с телефона или сохраняйте треки из каталога (⋮ → «Добавить в медиатеку»).',
                actionLabel: 'Добавить файлы с телефона',
                onAction: () => _addFiles(context),
              ),
            ),
            _Playlists(app: app),
            TrackListView(
              tracks: app.offlineTracks,
              empty: const EmptyState(
                icon: Icons.download_for_offline_outlined,
                text: 'Тут появятся треки, которые играют без интернета: '
                    'скачанные из каталога (⋮ → «Скачать для офлайна») '
                    'и файлы, добавленные с телефона.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Playlists extends StatelessWidget {
  const _Playlists({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.add)),
          title: const Text('Новый плейлист'),
          onTap: () async {
            final name = await promptText(context, 'Название плейлиста', '',
                okLabel: 'Создать');
            if (name != null && name.trim().isNotEmpty) {
              app.createPlaylist(name);
            }
          },
        ),
        if (app.playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Плейлистов пока нет. Создайте свой или перенесите из другого '
              'сервиса на вкладке «Импорт».',
              style: TextStyle(color: Colors.white60, height: 1.4),
            ),
          ),
        for (final pl in app.playlists)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.queue_music)),
            title: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${pl.trackIds.length} треков'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PlaylistPage(playlistId: pl.id))),
          ),
      ],
    );
  }
}
