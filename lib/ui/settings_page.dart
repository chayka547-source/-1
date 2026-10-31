import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _id = TextEditingController();
  int? _bytes;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _id.text = app.jamendoClientId;
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    final b = await context.read<AppState>().storageBytes();
    if (mounted) setState(() => _bytes = b);
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Каталог музыки (Jamendo)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Jamendo — каталог легальной музыки без рекламы. Для доступа нужен '
            'бесплатный ключ client_id: зарегистрируйтесь на сайте '
            'devportal.jamendo.com, создайте приложение и скопируйте ключ сюда.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _id,
            decoration: InputDecoration(
              labelText: 'client_id',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Вставить',
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  if (d?.text != null) _id.text = d!.text!.trim();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () {
                app.setClientId(_id.text);
                app.say('Сохранено');
              },
              child: const Text('Сохранить'),
            ),
          ),
          const SizedBox(height: 28),
          Text('Офлайн', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Скачано и добавлено с телефона: '
            '${_bytes == null ? '…' : fmtBytes(_bytes!)}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: app.downloads.isEmpty
                  ? null
                  : () async {
                      await app.clearDownloads();
                      await _refreshSize();
                      app.say('Загрузки удалены');
                    },
              child: const Text('Удалить все загрузки'),
            ),
          ),
          const SizedBox(height: 28),
          Text('О приложении', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Волна не содержит рекламы и не обходит подписки других сервисов. '
            'Музыка берётся из каталога Jamendo (лицензии Creative Commons) и '
            'из ваших собственных файлов. При переносе плейлиста из другого '
            'сервиса читаются только названия и исполнители, а аудио ищется '
            'в вашей медиатеке и в каталоге.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }
}
