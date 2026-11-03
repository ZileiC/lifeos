import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_provider.dart';
import '../providers.dart';

class AiSettingsSheet extends ConsumerStatefulWidget {
  const AiSettingsSheet({super.key});

  @override
  ConsumerState<AiSettingsSheet> createState() => _AiSettingsSheetState();
}

class _AiSettingsSheetState extends ConsumerState<AiSettingsSheet> {
  final TextEditingController _base = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _key = TextEditingController();

  List<AiProviderConfig> _providers = <AiProviderConfig>[];
  String? _activeId;
  AiProviderConfig? _selected;
  bool _loading = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final providerStore = ref.read(aiProviderStoreProvider);
    final keyStore = ref.read(aiKeyStoreProvider);
    final providers = await providerStore.readProviders();
    final activeId = await providerStore.readActiveId();
    final selected = providers.firstWhere(
      (provider) => provider.id == activeId,
      orElse: () => providers.first,
    );
    final key = await keyStore.read(selected.id);
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _activeId = selected.id;
      _selected = selected;
      _base.text = selected.baseUrl;
      _model.text = selected.model;
      _key.text = key ?? '';
      _loading = false;
    });
  }

  Future<void> _selectProvider(String id) async {
    final provider = _providers.firstWhere((item) => item.id == id);
    final key = await ref.read(aiKeyStoreProvider).read(provider.id);
    if (!mounted) return;
    setState(() {
      _activeId = id;
      _selected = provider;
      _base.text = provider.baseUrl;
      _model.text = provider.model;
      _key.text = key ?? '';
    });
  }

  void _addCustomProvider() {
    final id = 'custom-${DateTime.now().microsecondsSinceEpoch}';
    final provider = AiProviderConfig(
      id: id,
      name: 'Custom',
      protocol: AiProtocol.openai,
      baseUrl: 'https://',
      model: '',
    );
    setState(() {
      _providers = [..._providers, provider];
      _activeId = id;
      _selected = provider;
      _base.text = provider.baseUrl;
      _model.text = '';
      _key.text = '';
    });
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) return;
    final baseUrl = _base.text.trim();
    final model = _model.text.trim();
    if (baseUrl.isEmpty || baseUrl == 'https://' || model.isEmpty) {
      _toast('先填 base URL 和 model');
      return;
    }
    final updated = selected.copyWith(baseUrl: baseUrl, model: model);
    final providers = _providers
        .map((provider) => provider.id == updated.id ? updated : provider)
        .toList();
    final providerStore = ref.read(aiProviderStoreProvider);
    final keyStore = ref.read(aiKeyStoreProvider);
    await providerStore.writeProviders(providers);
    await providerStore.writeActiveId(updated.id);
    final key = _key.text.trim();
    if (key.isNotEmpty) {
      await keyStore.write(updated.id, key);
    }
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _selected = updated;
    });
    _toast('AI 设置已保存');
  }

  Future<void> _clearKey() async {
    final selected = _selected;
    if (selected == null) return;
    await ref.read(aiKeyStoreProvider).clear(selected.id);
    if (!mounted) return;
    setState(() => _key.clear());
    _toast('已清除该 provider 的 key');
  }

  Future<void> _testConnection() async {
    final selected = _selected;
    if (selected == null) return;
    final key = _key.text.trim();
    if (key.isEmpty) {
      _toast('先填 API key');
      return;
    }
    setState(() => _testing = true);
    try {
      final provider = selected.copyWith(
        baseUrl: _base.text.trim(),
        model: _model.text.trim(),
      );
      final models = await ref
          .read(aiClientProvider)
          .listModels(provider: provider, apiKey: key);
      if (!mounted) return;
      _toast(models.isEmpty
          ? '连接成功，但没返回模型列表'
          : '连接成功，可用模型：${models.map((m) => m.id).join(', ')}');
    } catch (error) {
      if (!mounted) return;
      _toast('连接失败：$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final height =
        (MediaQuery.sizeOf(context).height - viewInsets.bottom) * 0.9;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  Text('AI 设置', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '默认 DeepSeek；可添加其他 OpenAI-compatible provider。'
                    'key 只存本机安全存储，不写日志/DB/代码。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('ai-provider'),
                    initialValue: _activeId,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final provider in _providers)
                        DropdownMenuItem(
                          value: provider.id,
                          child: Text(provider.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _selectProvider(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('ai-add-custom'),
                      onPressed: _addCustomProvider,
                      icon: const Icon(Icons.add),
                      label: const Text('添加自定义 provider'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    key: const Key('ai-base'),
                    controller: _base,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://api.deepseek.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('ai-model'),
                    controller: _model,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      hintText: 'deepseek-flash / deepseek-v4-pro / 自定义',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('ai-key'),
                    controller: _key,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: const Key('ai-save'),
                        onPressed: _save,
                        child: const Text('保存'),
                      ),
                      OutlinedButton(
                        key: const Key('ai-test'),
                        onPressed: _testing ? null : _testConnection,
                        child: Text(_testing ? '测试中…' : '测试连接'),
                      ),
                      TextButton(
                        key: const Key('ai-clear-key'),
                        onPressed: _clearKey,
                        child: const Text('清除 key'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '隐私/成本：使用 AI 时，任务文本会发给当前 provider（默认 DeepSeek）；'
                    '费用由你的 key 自付；本 app 不做遥测；清 key 即禁用 AI。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
      ),
    );
  }
}
