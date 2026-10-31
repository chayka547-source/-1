import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import 'widgets.dart';

/// Поиск по своей медиатеке и по каталогу.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  List<Track> _local = [];
  List<Track> _remote = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    final app = context.read<AppState>();
    final lower = q.toLowerCase();
    setState(() {
      _searched = true;
      _loading = true;
      _error = null;
      _remote = [];
      _local = app.tracks.values
          .where((t) =>
              t.title.toLowerCase().contains(lower) ||
              t.artist.toLowerCase().contains(lower))
          .toList();
    });
    if (!app.jamendo.ready) {
      setState(() {
        _loading = false;
        _error = _local.isEmpty
            ? 'Укажите ключ Jamendo в настройках, чтобы искать в каталоге.'
            : null;
      });
      return;
    }
    try {
      final res = await app.jamendo.search(q, limit: 40);
      if (!mounted) return;
      setState(() {
        _remote = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось найти в каталоге: ${AppState.shortError(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Чтобы значки «скачано» и подсветка обновлялись.
    context.watch<AppState>();
    final children = <Widget>[];
    if (_local.isNotEmpty) {
      children.add(const _Header('В вашей медиатеке'));
      for (var i = 0; i < _local.length; i++) {
        children.add(TrackTile(track: _local[i], queue: _local, index: i));
      }
    }
    if (_remote.isNotEmpty) {
      children.add(const _Header('В каталоге'));
      for (var i = 0; i < _remote.length; i++) {
        children.add(TrackTile(track: _remote[i], queue: _remote, index: i));
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Песни, исполнители',
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _searched = false;
                  _local = [];
                  _remote = [];
                  _error = null;
                });
              },
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (!_searched
              ? const EmptyState(
                  icon: Icons.search,
                  text: 'Введите название песни или имя исполнителя.\n'
                      'Поиск идёт по вашей медиатеке и по каталогу.')
              : (children.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off,
                      text: _error ?? 'Ничего не найдено')
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.orangeAccent)),
                          ),
                        ...children,
                      ],
                    ))),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
}
