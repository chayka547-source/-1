import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'widgets.dart';

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final idx = app.playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Плейлист удалён')),
      );
    }
    final pl = app.playlists[idx];
    final tracks = app.playlistTracks(pl);
    return Scaffold(
      appBar: AppBar(
        title: Text(pl.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'rename') {
                final name = await promptText(context, 'Название плейлиста', pl.name);
                if (name != null) app.renamePlaylist(pl, name);
              } else if (v == 'download') {
                app.say('Скачиваю ${tracks.length} треков…');
                app.downloadMany(tracks);
              } else if (v == 'delete') {
                app.deletePlaylist(pl);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Переименовать')),
              PopupMenuItem(value: 'download', child: Text('Скачать всё для офлайна')),
              PopupMenuItem(value: 'delete', child: Text('Удалить плейлист')),
            ],
          ),
        ],
      ),
      body: TrackListView(
        tracks: tracks,
        playlist: pl,
        empty: const EmptyState(
          icon: Icons.queue_music,
          text: 'В плейлисте пока пусто. Добавляйте треки через меню ⋮ у любого трека.',
        ),
      ),
    );
  }
}
