import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  UserModel? get currentUser => _currentUser;
  String? get token => _token;
  List<InstanceModel> get instances => _instances;
  InstanceModel? get selectedInstance => _selectedInstance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null && _token != null;

  static const String _prefTokenKey = 'zelon_auth_token';
  static const String _prefUserKey = 'zelon_auth_user';
  static const String _prefSelectedInstKey = 'zelon_selected_inst';

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
        final selId = prefs.getString(_prefSelectedInstKey);
        if (selId != null) {
          _selectedInstance = _instances.where((x) => x.id == selId).firstOrNull;
        }
        if (_selectedInstance == null && _instances.isNotEmpty) {
          _selectedInstance = _instances.first;
        }
        notifyListeners();
        // Background verify & refresh
        await refreshUser();
        await refreshInstances();
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

  Future<void> refreshUser() async {
    try {
      _currentUser = await api.getMe();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUserKey, jsonEncode(_currentUser!.toJson()));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshInstances() async {
    try {
      _instances = await api.getInstances();
      await CacheService.saveInstances(_instances);
      final prefs = await SharedPreferences.getInstance();
      final selId = prefs.getString(_prefSelectedInstKey);
      if (selId != null) {
        _selectedInstance = _instances.where((x) => x.id == selId).firstOrNull;
      }
      if (_selectedInstance == null && _instances.isNotEmpty) {
        _selectedInstance = _instances.first;
      }
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

  Future<void> logout() async {
    realtime.disconnect();
    await api.logout();
    _token = null;
    _currentUser = null;
    _selectedInstance = null;
    _instances = [];
    api.setToken(null);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefTokenKey);
    await prefs.remove(_prefUserKey);
    await prefs.remove(_prefSelectedInstKey);
    notifyListeners();
  }
}
