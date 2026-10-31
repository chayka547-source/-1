import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../import/link_importer.dart';
import '../import/matcher.dart';
import 'playlist_page.dart';
import 'widgets.dart';

enum _Stage { idle, reading, matching, done }

/// Перенос плейлиста/альбома по ссылке или текстовому списку.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _name = TextEditingController();

  _Stage _stage = _Stage.idle;
  String? _error;
  ImportedList? _list;
  List<MatchResult> _results = [];
  String? _matchError;
  int _done = 0;
  bool _download = true;

  /// Ссылка из буфера обмена, которую можно перенести одним нажатием.
  String? _clipLink;
  String? _dismissedLink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tabIndex.addListener(_onTab);
  }

  @override
  void dispose() {
    tabIndex.removeListener(_onTab);
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _name.dispose();
    super.dispose();
  }

  void _onTab() {
    if (tabIndex.value == 3) _checkClipboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && tabIndex.value == 3) {
      _checkClipboard();
    }
  }

  Future<void> _checkClipboard() async {
    // Android отдаёт буфер обмена только после того, как окно получило фокус.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final link = d?.text == null ? null : LinkImporter.recognizedLink(d!.text!);
      if (!mounted) return;
      if (link != null && link != _dismissedLink && link != _input.text.trim()) {
        setState(() => _clipLink = link);
      }
    } catch (_) {}
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _input.text = d!.text!);
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    final text = _input.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _stage = _Stage.reading;
      _error = null;
      _list = null;
      _results = [];
      _matchError = null;
    });
    try {
      final link = LinkImporter.extractLink(text);
      final list = link != null
          ? await LinkImporter.fromLink(link)
          : LinkImporter.fromText(text);
      if (list.items.isEmpty) {
        throw ImportException('Список пуст — не нашлось ни одного трека');
      }
      if (!mounted) return;
      setState(() {
        _list = list;
        _stage = _Stage.matching;
        _done = 0;
        _name.text = list.name;
      });
      final run = await Matcher.run(
        list.items,
        pool: app.tracks.values.toList(),
        jamendo: app.jamendo,
        onProgress: (d, total) {
          if (mounted) setState(() => _done = d);
        },
      );
      if (!mounted) return;
      setState(() {
        _results = run.results;
        _matchError = run.error;
        _stage = _Stage.done;
      });
    } on ImportException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _stage = _Stage.idle;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Что-то пошло не так: ${AppState.shortError(e)}';
          _stage = _Stage.idle;
        });
      }
    }
  }

  void _create() {
    final app = context.read<AppState>();
    final found = _results.where((r) => r.found).map((r) => r.track!).toList();
    if (found.isEmpty) return;
    final pl = app.createPlaylist(_name.text, found);
    if (_download) unawaited(app.downloadMany(found));
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlaylistPage(playlistId: pl.id)));
    setState(() {
      _stage = _Stage.idle;
      _results = [];
      _list = null;
      _input.clear();
    });
  }

  Future<void> _copyMissing() async {
    final lines = _results
        .where((r) => !r.found)
        .map((r) => r.item.artist.isEmpty
            ? r.item.title
            : '${r.item.artist} - ${r.item.title}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: lines));
    if (mounted) context.read<AppState>().say('Список ненайденных скопирован');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final found = _results.where((r) => r.found).length;
    final busy = _stage == _Stage.reading || _stage == _Stage.matching;
    return Scaffold(
      appBar: AppBar(title: const Text('Перенос плейлиста')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_clipLink != null && !busy)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('В буфере обмена ссылка на музыку',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_clipLink!,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _dismissedLink = _clipLink;
                            _clipLink = null;
                          }),
                          child: const Text('Скрыть'),
                        ),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _input.text = _clipLink!;
                              _clipLink = null;
                            });
                            _start();
                          },
                          child: const Text('Перенести'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const Text(
            'Вставьте ссылку на альбом или плейлист из Яндекс Музыки, '
            'YouTube Music или Spotify. Для VK Музыки и других сервисов '
            'вставьте список песен текстом: «Исполнитель - Название», '
            'по одной на строке.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            minLines: 3,
            maxLines: 8,
            enabled: !busy,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'https://music.yandex.ru/album/…',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : _paste,
                icon: const Icon(Icons.paste),
                label: const Text('Вставить'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _start,
                  icon: const Icon(Icons.search),
                  label: const Text('Найти треки'),
                ),
              ),
            ],
          ),
          if (!app.jamendo.ready)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Ключ Jamendo не указан (Настройки): поиск пойдёт только по '
                'вашей медиатеке и файлам с телефона.',
                style: TextStyle(color: Colors.orangeAccent, height: 1.4),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, height: 1.4)),
            ),
          if (_stage == _Stage.reading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_stage == _Stage.matching && _list != null) ...[
            const SizedBox(height: 24),
            Text('Ищу треки: $_done из ${_list!.items.length}'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: _list!.items.isEmpty ? null : _done / _list!.items.length),
          ],
          if (_stage == _Stage.done && _list != null) ...[
            const SizedBox(height: 24),
            Text(
              'Найдено $found из ${_results.length} (${_list!.service})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_matchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Поиск в каталоге не сработал: $_matchError',
                    style: const TextStyle(color: Colors.orangeAccent)),
              ),
            if (found == 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Совпадений нет. Каталог Jamendo — это независимые артисты, '
                  'популярных хитов в нём обычно нет. Добавьте свои файлы '
                  'в «Медиатеке» и повторите перенос: приложение сопоставит '
                  'названия с ними.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ),
            if (found > 0) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Название плейлиста',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _download,
                onChanged: (v) => setState(() => _download = v ?? false),
                title: const Text('Скачать для офлайна'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _create,
                  child: Text('Создать плейлист ($found)'),
                ),
              ),
            ],
            if (found < _results.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _copyMissing,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Скопировать ненайденные'),
                ),
              ),
            const Divider(),
            for (final r in _results)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.found ? Icons.check_circle : Icons.remove_circle_outline,
                  color: r.found ? Colors.greenAccent : Colors.white38,
                ),
                title: Text(
                  r.item.artist.isEmpty
                      ? r.item.title
                      : '${r.item.artist} — ${r.item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: r.found ? null : Colors.white54),
                ),
                subtitle: Text(
                  r.found ? 'Нашёлся: ${r.via}' : 'Не найден',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
