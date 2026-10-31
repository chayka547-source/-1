import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';

/// Какая вкладка открыта (0 — Главная, 1 — Поиск, 2 — Медиатека, 3 — Импорт).
final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

String fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String fmtBytes(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}

/// Обложка трека (или заглушка).
class Cover extends StatelessWidget {
  const Cover({super.key, this.url, this.size = 48, this.radius = 6});

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: const Color(0xFF242424),
      child: Icon(Icons.music_note, color: Colors.white38, size: size * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (url == null || url!.isEmpty)
          ? placeholder
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : placeholder,
            ),
    );
  }
}

/// Кнопка «играть/пауза», показывает индикатор загрузки.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return StreamBuilder<PlayerState>(
      stream: app.player.playerStateStream,
      builder: (context, snap) {
        final st = snap.data;
        final loading = st != null &&
            (st.processingState == ProcessingState.loading ||
                st.processingState == ProcessingState.buffering);
        if (loading) {
          return SizedBox(
            width: size,
            height: size,
            child: Padding(
              padding: EdgeInsets.all(size * 0.25),
              child: const CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        final playing = st?.playing ?? false;
        return IconButton(
          iconSize: size,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
          onPressed: app.togglePlay,
        );
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white38),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4)),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

Future<String?> promptText(
  BuildContext context,
  String title,
  String initial, {
  String okLabel = 'Готово',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text), child: Text(okLabel)),
      ],
    ),
  );
}

Future<void> showAddToPlaylist(BuildContext context, Track t) {
  final app = context.read<AppState>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Новый плейлист'),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await promptText(context, 'Название плейлиста', '');
                if (name != null && name.trim().isNotEmpty) {
                  app.createPlaylist(name, [t]);
                  app.say('Плейлист «${name.trim()}» создан');
                }
              },
            ),
            for (final pl in app.playlists)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(pl.name),
                subtitle: Text('${pl.trackIds.length} треков'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.addToPlaylist(pl, t);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showTrackMenu(BuildContext context, Track t,
    {UserPlaylist? playlist}) {
  final app = context.read<AppState>();
  final downloaded = app.isDownloaded(t);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Cover(url: t.coverUrl, size: 44),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            if (!t.isLocal)
              ListTile(
                leading: Icon(app.isFavorite(t.id)
                    ? Icons.favorite
                    : Icons.favorite_border),
                title: Text(app.isFavorite(t.id)
                    ? 'Убрать из медиатеки'
                    : 'Добавить в медиатеку'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.toggleFavorite(t);
                },
              ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Добавить в плейлист'),
              onTap: () {
                Navigator.pop(ctx);
                showAddToPlaylist(context, t);
              },
            ),
            if (!t.isLocal && !downloaded)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Скачать для офлайна'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.download(t);
                },
              ),
            if (!t.isLocal && downloaded)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Удалить загрузку'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.removeDownload(t);
                },
              ),
            if (playlist != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Убрать из плейлиста'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.removeFromPlaylist(playlist, t);
                },
              ),
            if (t.isLocal)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Удалить с устройства'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.removeTrack(t);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Строка трека в списках.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.playlist,
  });

  final Track track;
  final List<Track> queue;
  final int index;
  final UserPlaylist? playlist;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isCurrent = app.current?.id == track.id;
    final progress = app.downloadProgress[track.id];
    final scheme = Theme.of(context).colorScheme;
    final dur = track.durationSec > 0
        ? ' · ${fmtDuration(Duration(seconds: track.durationSec))}'
        : '';
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: Cover(url: track.coverUrl, size: 48),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCurrent ? scheme.primary : null,
        ),
      ),
      subtitle: Row(
        children: [
          if (!track.isLocal && app.isDownloaded(track))
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.download_done, size: 14, color: Colors.white54),
            ),
          Expanded(
            child: Text('${track.artist}$dur',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: progress != null
          ? Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null, strokeWidth: 2.5),
              ),
            )
          : IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => showTrackMenu(context, track, playlist: playlist),
            ),
      onTap: () => app.playQueue(queue, index),
    );
  }
}

/// Список треков с кнопками «Слушать» и «Вперемешку».
class TrackListView extends StatelessWidget {
  const TrackListView({
    super.key,
    required this.tracks,
    this.playlist,
    this.empty,
  });

  final List<Track> tracks;
  final UserPlaylist? playlist;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return empty ?? const SizedBox.shrink();
    }
    final app = context.read<AppState>();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: tracks.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: () => app.playQueue(tracks, 0),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Слушать'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => app.playShuffled(tracks),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Вперемешку'),
                ),
              ],
            ),
          );
        }
        return TrackTile(
          track: tracks[i - 1],
          queue: tracks,
          index: i - 1,
          playlist: playlist,
        );
      },
    );
  }
}
