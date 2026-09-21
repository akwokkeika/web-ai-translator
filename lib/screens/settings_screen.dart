import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ai_provider.dart';
import '../services/settings_store.dart';
import '../services/translator_factory.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AiProvider _provider;
  late final TextEditingController _geminiApiKey;
  late final TextEditingController _geminiModel;
  late final TextEditingController _geminiBaseUrl;
  late final TextEditingController _openaiApiKey;
  late final TextEditingController _openaiModel;
  late final TextEditingController _openaiBaseUrl;
  late final TextEditingController _ollamaApiKey;
  late final TextEditingController _ollamaModel;
  late final TextEditingController _ollamaBaseUrl;
  late final TextEditingController _minFont;
  late String _language;
  bool _obscureGemini = true;
  bool _obscureOpenai = true;
  bool _obscureOllama = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _provider = settings.provider;
    _geminiApiKey = TextEditingController(text: settings.geminiApiKey);
    _geminiModel = TextEditingController(text: settings.geminiModel);
    _geminiBaseUrl = TextEditingController(text: settings.geminiBaseUrl);
    _openaiApiKey = TextEditingController(text: settings.openaiApiKey);
    _openaiModel = TextEditingController(text: settings.openaiModel);
    _openaiBaseUrl = TextEditingController(text: settings.openaiBaseUrl);
    _ollamaApiKey = TextEditingController(text: settings.ollamaApiKey);
    _ollamaModel = TextEditingController(text: settings.ollamaModel);
    _ollamaBaseUrl = TextEditingController(text: settings.ollamaBaseUrl);
    _minFont = TextEditingController(text: '${settings.minFontPx}');
    _language = settings.targetLanguage;
  }

  @override
  void dispose() {
    _geminiApiKey.dispose();
    _geminiModel.dispose();
    _geminiBaseUrl.dispose();
    _openaiApiKey.dispose();
    _openaiModel.dispose();
    _openaiBaseUrl.dispose();
    _ollamaApiKey.dispose();
    _ollamaModel.dispose();
    _ollamaBaseUrl.dispose();
    _minFont.dispose();
    super.dispose();
  }

  int _parsedMinFont() {
    return int.tryParse(_minFont.text.trim()) ?? widget.settings.minFontPx;
  }

  Future<void> _persist() {
    return widget.settings.save(
      provider: _provider,
      geminiApiKey: _geminiApiKey.text,
      geminiModel: _geminiModel.text,
      geminiBaseUrl: _geminiBaseUrl.text,
      openaiApiKey: _openaiApiKey.text,
      openaiModel: _openaiModel.text,
      openaiBaseUrl: _openaiBaseUrl.text,
      ollamaApiKey: _ollamaApiKey.text,
      ollamaModel: _ollamaModel.text,
      ollamaBaseUrl: _ollamaBaseUrl.text,
      targetLanguage: _language,
      minFontPx: _parsedMinFont(),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _persist();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已儲存')),
    );
    Navigator.pop(context);
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    await _persist();
    try {
      final reply = await createTranslator(_provider).ping(widget.settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('連線成功：$reply')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _nudgeFont(int delta) {
    final next = SettingsStore.clampFont(_parsedMinFont() + delta);
    _minFont.text = '$next';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Text(
            '可切換 Gemini、OpenAI，或本機 Ollama。金鑰只存在這台裝置，模型名稱請自行填寫。',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          const Text('API 來源'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final provider in AiProvider.values)
                ChoiceChip(
                  label: Text(provider.label),
                  selected: _provider == provider,
                  onSelected: (_) => setState(() => _provider = provider),
                ),
            ],
          ),
          const SizedBox(height: 20),
          ..._providerFields(),
          const SizedBox(height: 20),
          const Text('譯文最小字級 (px)'),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: () => _nudgeFont(-1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _minFont,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(suffixText: 'px'),
                ),
              ),
              IconButton(
                onPressed: () => _nudgeFont(1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '以畫面寬度完整顯示漫畫時為準。譯文會先用這個大小換行；只有氣泡太小、換行後仍塞不下，才會再自動縮小。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),
          const Text('目標語言'),
          const SizedBox(height: 8),
          DropdownMenu<String>(
            initialSelection: SettingsStore.languages.contains(_language)
                ? _language
                : SettingsStore.defaultLanguage,
            dropdownMenuEntries: [
              for (final lang in SettingsStore.languages)
                DropdownMenuEntry(value: lang, label: lang),
            ],
            onSelected: (value) {
              if (value == null) return;
              setState(() => _language = value);
            },
            expandedInsets: EdgeInsets.zero,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing || _saving ? null : _test,
                  child: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('測試連線'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.stamp,
                    foregroundColor: AppColors.paper,
                  ),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '儲存中…' : '儲存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _providerFields() {
    switch (_provider) {
      case AiProvider.gemini:
        return [
          const Text('Gemini API Key'),
          const SizedBox(height: 8),
          _secretField(
            controller: _geminiApiKey,
            hint: 'AIza...',
            obscure: _obscureGemini,
            onToggle: () => setState(() => _obscureGemini = !_obscureGemini),
          ),
          const SizedBox(height: 20),
          const Text('模型'),
          const SizedBox(height: 8),
          TextField(
            controller: _geminiModel,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: '例如 gemini-2.5-flash',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '請自行填寫 Google 模型 ID，不會預設選模型。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),
          const Text('Endpoint（進階）'),
          const SizedBox(height: 8),
          TextField(
            controller: _geminiBaseUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: SettingsStore.defaultGeminiBaseUrl,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '預設會請求 {endpoint}/models/{model}:generateContent。若整段貼上含 :generateContent 的完整網址，則直接使用。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
        ];
      case AiProvider.openai:
        return [
          const Text('OpenAI API Key'),
          const SizedBox(height: 8),
          _secretField(
            controller: _openaiApiKey,
            hint: 'sk-...',
            obscure: _obscureOpenai,
            onToggle: () => setState(() => _obscureOpenai = !_obscureOpenai),
          ),
          const SizedBox(height: 20),
          const Text('模型'),
          const SizedBox(height: 8),
          TextField(
            controller: _openaiModel,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: '例如 gpt-4o',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '請填寫支援看圖的模型 ID，例如 gpt-4o。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),
          const Text('Endpoint（進階）'),
          const SizedBox(height: 8),
          TextField(
            controller: _openaiBaseUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: SettingsStore.defaultOpenAiBaseUrl,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '預設請求 {endpoint}/chat/completions。相容 OpenAI 的服務也可填，例如 Groq、LM Studio，或 Ollama 的 /v1。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
        ];
      case AiProvider.ollama:
        return [
          const Text('Ollama 位址'),
          const SizedBox(height: 8),
          TextField(
            controller: _ollamaBaseUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: SettingsStore.defaultOllamaBaseUrl,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '本機預設 http://127.0.0.1:11434。Android 模擬器請改 10.0.2.2；實體手機請填電腦區網 IP，並讓 Ollama 監聽 0.0.0.0。若填 /v1，會改走 OpenAI 相容接口。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),
          const Text('模型'),
          const SizedBox(height: 8),
          TextField(
            controller: _ollamaModel,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: '例如 llava 或 qwen2.5vl',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '請填本機已安裝、且支援看圖的模型名稱。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),
          const Text('API Key（選填）'),
          const SizedBox(height: 8),
          _secretField(
            controller: _ollamaApiKey,
            hint: '本機通常留空',
            obscure: _obscureOllama,
            onToggle: () => setState(() => _obscureOllama = !_obscureOllama),
          ),
          const SizedBox(height: 6),
          const Text(
            '只有走反向代理或需要 Bearer token 時才填。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
        ];
    }
  }

  Widget _secretField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }
}
