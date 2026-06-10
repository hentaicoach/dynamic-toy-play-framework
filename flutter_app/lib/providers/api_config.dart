import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// API 连接模式
enum ApiMode { hermes, deepseek }

/// API 配置状态
///
/// DeepSeek 直连模式：Key 存本地 SharedPreferences，完全不依赖本地服务。
/// Hermes 模式：通过 WS 连接本地 FastAPI 服务。
/// 首次可从 Hermes 服务可选导入 Key（如果服务在线），之后离线可用。
class ApiConfig extends ChangeNotifier {
  static const _keyMode = 'api_mode';
  static const _keyDeepseekKey = 'deepseek_api_key';
  static const _keyDeepseekModel = 'deepseek_model';
  static const _keyDeepseekBaseUrl = 'deepseek_base_url';
  static const _keyHermesHost = 'hermes_host';
  static const _keyHermesPort = 'hermes_port';
  static const _keyDebugMode = 'debug_mode';

  ApiMode _mode = ApiMode.hermes;
  String _deepseekApiKey = 'sk-c417b62c66c942c3a1e543de1f63185a';
  String _deepseekModel = 'deepseek-v4-flash';
  String _deepseekBaseUrl = 'https://api.deepseek.com/v1';
  String _hermesHost = '10.0.2.2';
  int _hermesPort = 8765;
  bool _loaded = false;
  bool _debugMode = true;

  // ── Getters ──
  ApiMode get mode => _mode;
  bool get isHermes => _mode == ApiMode.hermes;
  bool get isDeepseek => _mode == ApiMode.deepseek;
  String get deepseekApiKey => _deepseekApiKey;
  String get deepseekModel => _deepseekModel;
  String get deepseekBaseUrl => _deepseekBaseUrl;
  String get hermesHost => _hermesHost;
  int get hermesPort => _hermesPort;
  bool get hasDeepseekKey => _deepseekApiKey.isNotEmpty;
  bool get loaded => _loaded;
  bool get debugMode => _debugMode;

  /// 切换调试模式（true=使用FakeDriver/UI模拟, false=真实BLE，暂未实现）
  void setDebugMode(bool v) {
    _debugMode = v;
    _save();
    notifyListeners();
  }

  // ── 初始化：从本地存储读取 ──

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = ApiMode.values.firstWhere(
      (e) => e.name == prefs.getString(_keyMode),
      orElse: () => ApiMode.hermes,
    );
    _deepseekApiKey = prefs.getString(_keyDeepseekKey) ?? _deepseekApiKey;
    if (_deepseekApiKey.isEmpty) _deepseekApiKey = 'sk-c417b62c66c942c3a1e543de1f63185a';
    _deepseekModel = prefs.getString(_keyDeepseekModel) ?? 'deepseek-v4-flash';
    _deepseekBaseUrl =
        prefs.getString(_keyDeepseekBaseUrl) ?? 'https://api.deepseek.com/v1';
    _hermesHost = prefs.getString(_keyHermesHost) ?? '10.0.2.2';
    _hermesPort = prefs.getInt(_keyHermesPort) ?? 8765;
    _debugMode = prefs.getBool(_keyDebugMode) ?? true;
    _loaded = true;
    notifyListeners();
    debugPrint('[ApiConfig] Loaded from local storage, mode=$_mode, hasKey=${_deepseekApiKey.isNotEmpty}');
  }

  // ── 可选：从 Hermes 服务导入 Key（服务在线时方便初始配置） ──

  Future<bool> importFromHermes() async {
    try {
      final uri = Uri.parse('http://$_hermesHost:$_hermesPort/api/config');
      final resp = await http.get(uri).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final key = (data['deepseek_api_key'] as String? ?? '');
        if (key.isNotEmpty && _deepseekApiKey.isEmpty) {
          _deepseekApiKey = key;
          _save();
          debugPrint('[ApiConfig] Imported key from Hermes server');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[ApiConfig] Import from Hermes skipped: $e');
    }
    return false;
  }

  // ── 切换模式 ──

  void setMode(ApiMode mode) {
    _mode = mode;
    _save();
    notifyListeners();
  }

  // ── DeepSeek 配置（本地存储，不依赖任何服务） ──

  void setDeepseekKey(String key) {
    _deepseekApiKey = key;
    _save();
    notifyListeners();
  }

  void setDeepseekModel(String model) {
    _deepseekModel = model;
    _save();
    notifyListeners();
  }

  void setDeepseekBaseUrl(String url) {
    _deepseekBaseUrl = url;
    _save();
    notifyListeners();
  }

  void setHermesHost(String host, int port) {
    _hermesHost = host;
    _hermesPort = port;
    _save();
    notifyListeners();
  }

  // ── 持久化到 SharedPreferences ──

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, _mode.name);
    await prefs.setString(_keyDeepseekKey, _deepseekApiKey);
    await prefs.setString(_keyDeepseekModel, _deepseekModel);
    await prefs.setString(_keyDeepseekBaseUrl, _deepseekBaseUrl);
    await prefs.setString(_keyHermesHost, _hermesHost);
    await prefs.setInt(_keyHermesPort, _hermesPort);
    await prefs.setBool(_keyDebugMode, _debugMode);
  }
}
