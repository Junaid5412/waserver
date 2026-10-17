import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/instance.dart';
import 'api_service.dart';
import 'cache_service.dart';
import 'realtime_service.dart';

class AuthService extends ChangeNotifier {
  final ApiService api;
  late final RealtimeService realtime;

  UserModel? _currentUser;
  String? _token;
  List<InstanceModel> _instances = [];
  InstanceModel? _selectedInstance;
  bool _isLoading = false;
  String? _errorMessage;
  String? currentOpenChatId;

  UserModel? get currentUser => _currentUser;
  String? get token => _token;
  List<InstanceModel> get instances => _instances;
  InstanceModel? get selectedInstance => _selectedInstance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null && _token != null;
  Map<String, String> get apiHeaders => api.authHeaders;

  static const String _prefTokenKey = 'zelon_auth_token';
  static const String _prefUserKey = 'zelon_auth_user';
  static const String _prefSelectedInstKey = 'zelon_selected_inst';
  static const String _prefDefaultInstKey = 'zelon_default_instance_id';

  String? _defaultInstanceId;
  String? get defaultInstanceId => _defaultInstanceId;

  AuthService({required this.api}) {
    realtime = RealtimeService(api: api);
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_prefTokenKey);
      final userStr = prefs.getString(_prefUserKey);
      if (_token != null && userStr != null) {
        api.setToken(_token);
        _currentUser = UserModel.fromJson(jsonDecode(userStr));
        // Load cached instances immediately for fast startup
        _instances = await CacheService.getCachedInstances();
        _defaultInstanceId = prefs.getString(_prefDefaultInstKey);
        final selId = prefs.getString(_prefSelectedInstKey);
        if (_defaultInstanceId != null && _instances.any((x) => x.id == _defaultInstanceId)) {
          _selectedInstance = _instances.firstWhere((x) => x.id == _defaultInstanceId);
        } else if (selId != null) {
          _selectedInstance = _instances.where((x) => x.id == selId).firstOrNull;
        }
        if (_selectedInstance == null && _instances.isNotEmpty) {
          _selectedInstance = _instances.first;
        }
        notifyListeners();
        // Background verify & refresh
        await refreshUser();
        // refreshUser clears the session if the server rejected the token.
        if (_token != null && _currentUser != null) {
          await refreshInstances();
        }
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final res = await api.login(email, password);
      _token = res['token']?.toString() ?? 'session_active';
      api.setToken(_token);

      if (res['user'] != null && res['user'] is Map) {
        _currentUser = UserModel.fromJson(Map<String, dynamic>.from(res['user']));
      } else {
        _currentUser = await api.getMe();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefTokenKey, _token!);
      await prefs.setString(_prefUserKey, jsonEncode(_currentUser!.toJson()));

      await refreshInstances();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Re-fetches the signed-in user's profile.
  ///
  /// If the server explicitly rejects the stored session (HTTP 401/403) the
  /// local session is cleared so the app falls back to the LoginScreen.
  /// Network failures / timeouts / other server errors keep the cached user.
  Future<void> refreshUser() async {
    try {
      // Called directly (instead of api.getMe) so the HTTP status code is
      // visible: getMe throws the same generic Exception for every non-200.
      final res = await http
          .get(Uri.parse(ApiConfig.meUrl), headers: api.authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401 || res.statusCode == 403) {
        realtime.disconnect();
        await _clearLocalSession();
        notifyListeners();
        return;
      }
      if (res.statusCode != 200) return;
      _currentUser = UserModel.fromJson(jsonDecode(res.body));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUserKey, jsonEncode(_currentUser!.toJson()));
      notifyListeners();
    } catch (_) {}
  }

  /// Clears the in-memory and persisted session (token, user, instance
  /// selection). Never touches the network.
  Future<void> _clearLocalSession() async {
    _token = null;
    _currentUser = null;
    _selectedInstance = null;
    _instances = [];
    api.setToken(null);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTokenKey);
      await prefs.remove(_prefUserKey);
      await prefs.remove(_prefSelectedInstKey);
    } catch (_) {}
  }

  Future<void> refreshInstances() async {
    try {
      _instances = await api.getInstances();
      await CacheService.saveInstances(_instances);
      final prefs = await SharedPreferences.getInstance();
      _defaultInstanceId = prefs.getString(_prefDefaultInstKey);
      final selId = prefs.getString(_prefSelectedInstKey);

      InstanceModel? findById(String? id) {
        if (id == null) return null;
        return _instances.where((x) => x.id == id).firstOrNull;
      }

      // Always re-bind the selection to the freshly loaded object (same id) so
      // status/name/phone updates are visible; otherwise fall back to the
      // default instance, the persisted selection, then the first instance.
      _selectedInstance = findById(_selectedInstance?.id) ??
          findById(_defaultInstanceId) ??
          findById(selId) ??
          (_instances.isNotEmpty ? _instances.first : null);
      if (_selectedInstance != null) {
        realtime.connect(_selectedInstance!.id);
      }
      notifyListeners();
    } catch (_) {}
  }

  void selectInstance(InstanceModel inst) async {
    _selectedInstance = inst;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSelectedInstKey, inst.id);
    realtime.connect(inst.id);
    notifyListeners();
  }

  Future<void> setDefaultInstance(String instanceId) async {
    _defaultInstanceId = instanceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDefaultInstKey, instanceId);
    final inst = _instances.where((x) => x.id == instanceId).firstOrNull;
    if (inst != null) {
      selectInstance(inst);
    } else {
      notifyListeners();
    }
  }

  Future<void> deleteInstance(String instanceId) async {
    await api.deleteInstance(instanceId);
    final prefs = await SharedPreferences.getInstance();
    if (_defaultInstanceId == instanceId) {
      _defaultInstanceId = null;
      await prefs.remove(_prefDefaultInstKey);
    }
    final selId = prefs.getString(_prefSelectedInstKey);
    if (selId == instanceId) {
      await prefs.remove(_prefSelectedInstKey);
    }
    if (_selectedInstance?.id == instanceId) {
      _selectedInstance = null;
    }
    await refreshInstances();
  }

  Future<void> logout() async {
    realtime.disconnect();
    // Best-effort server sign-out: never let an unreachable/slow server block
    // the local logout.
    try {
      await api.logout().timeout(const Duration(seconds: 3));
    } catch (_) {}
    await _clearLocalSession();
    notifyListeners();
  }
}
