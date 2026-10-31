import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'player_page.dart';
import 'widgets.dart';

/// Мини-плеер над нижним меню. Нажмите, чтобы открыть большой плеер.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.current;
    if (t == null) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFF1A1A1A),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const PlayerPage(),
        )),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Cover(url: t.coverUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                  const PlayPauseButton(size: 40),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: app.next,
                  ),
                ],
              ),
            ),
            StreamBuilder<Duration>(
              stream: app.player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final total = app.player.duration ??
                    Duration(seconds: t.durationSec);
                final double v = total.inMilliseconds > 0
                    ? (pos.inMilliseconds / total.inMilliseconds)
                        .clamp(0.0, 1.0)
                        .toDouble()
                    : 0.0;
                return LinearProgressIndicator(value: v, minHeight: 2);
              },
            ),
          ],
        ),
      ),
    );
  }
}
