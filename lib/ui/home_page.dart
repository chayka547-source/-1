import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// Главная: популярное за неделю из каталога.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<List<Track>>? _future;
  String _loadedFor = '';

  Future<void> _refresh(AppState app) async {
    setState(() {
      _future = app.jamendo.ready ? app.jamendo.popular(limit: 40) : null;
    });
    try {
      await _future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.jamendoClientId != _loadedFor) {
      _loadedFor = app.jamendoClientId;
      _future = app.jamendo.ready ? app.jamendo.popular(limit: 40) : null;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Волна', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: _body(app),
    );
  }

  Widget _body(AppState app) {
    if (!app.jamendo.ready) {
      return EmptyState(
        icon: Icons.vpn_key_outlined,
        text: 'Чтобы слушать музыку из каталога, укажите бесплатный ключ '
            'Jamendo в настройках. Файлы с телефона можно добавить '
            'в «Медиатеке» и без ключа.',
        actionLabel: 'Открыть настройки',
        onAction: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
      );
    }
    return FutureBuilder<List<Track>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off,
            text: 'Не удалось загрузить каталог: ${AppState.shortError(snap.error!)}\n\n'
                'Скачанные треки доступны офлайн в «Медиатеке».',
            actionLabel: 'Открыть медиатеку',
            onAction: () => tabIndex.value = 2,
          );
        }
        final list = snap.data ?? const <Track>[];
        return RefreshIndicator(
          onRefresh: () => _refresh(app),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: list.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('Популярное на этой неделе',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                );
              }
              return TrackTile(track: list[i - 1], queue: list, index: i - 1);
            },
          ),
        );
      },
    );
  }
}
