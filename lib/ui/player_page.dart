import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'widgets.dart';

/// Большой плеер на весь экран.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.current;
    final scheme = Theme.of(context).colorScheme;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Ничего не играет')),
      );
    }
    final coverSize = min(MediaQuery.of(context).size.width - 48, 340.0);
    final progress = app.downloadProgress[t.id];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Сейчас играет'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Center(child: Cover(url: t.coverUrl, size: coverSize, radius: 16)),
            const SizedBox(height: 28),
            Text(t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 12),
            SeekBar(fallbackSeconds: t.durationSec),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                StreamBuilder<bool>(
                  stream: app.player.shuffleModeEnabledStream,
                  builder: (context, snap) => IconButton(
                    icon: Icon(Icons.shuffle,
                        color: (snap.data ?? false) ? scheme.primary : null),
                    onPressed: app.toggleShuffle,
                  ),
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: app.previous,
                ),
                const PlayPauseButton(size: 72),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next),
                  onPressed: app.next,
                ),
                StreamBuilder<LoopMode>(
                  stream: app.player.loopModeStream,
                  builder: (context, snap) {
                    final m = snap.data ?? LoopMode.off;
                    return IconButton(
                      icon: Icon(
                        m == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                        color: m == LoopMode.off ? null : scheme.primary,
                      ),
                      onPressed: app.cycleRepeat,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!t.isLocal)
                  IconButton(
                    tooltip: 'В медиатеку',
                    icon: Icon(
                      app.isFavorite(t.id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: app.isFavorite(t.id) ? scheme.primary : null,
                    ),
                    onPressed: () => app.toggleFavorite(t),
                  ),
                if (!t.isLocal)
                  if (progress != null)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            value: progress > 0 ? progress : null,
                            strokeWidth: 2.5),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: app.isDownloaded(t)
                          ? 'Скачано — нажмите, чтобы удалить'
                          : 'Скачать для офлайна',
                      icon: Icon(
                        app.isDownloaded(t)
                            ? Icons.download_done
                            : Icons.download_outlined,
                        color: app.isDownloaded(t) ? scheme.primary : null,
                      ),
                      onPressed: () => app.isDownloaded(t)
                          ? app.removeDownload(t)
                          : app.download(t),
                    ),
                IconButton(
                  tooltip: 'В плейлист',
                  icon: const Icon(Icons.playlist_add),
                  onPressed: () => showAddToPlaylist(context, t),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Полоса перемотки с таймингами.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, this.fallbackSeconds = 0});

  final int fallbackSeconds;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = context.read<AppState>().player;
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, dSnap) {
        final total = dSnap.data ?? Duration(seconds: widget.fallbackSeconds);
        final maxMs = max(total.inMilliseconds.toDouble(), 1.0);
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, pSnap) {
            final pos = pSnap.data ?? Duration.zero;
            final value = (_drag ?? pos.inMilliseconds.toDouble())
                .clamp(0.0, maxMs)
                .toDouble();
            return Column(
              children: [
                Slider(
                  min: 0,
                  max: maxMs,
                  value: value,
                  onChanged: (v) => setState(() => _drag = v),
                  onChangeEnd: (v) {
                    player.seek(Duration(milliseconds: v.round()));
                    setState(() => _drag = null);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(fmtDuration(Duration(milliseconds: value.round())),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12)),
                      Text(
                          total.inMilliseconds > 0 ? fmtDuration(total) : '--:--',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
