import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockService extends ChangeNotifier {
  static const String _prefLockEnabledKey = 'zelon_lock_enabled';
  static const String _prefPinKey = 'zelon_lock_pin';
  static const String _prefBiometricsEnabledKey = 'zelon_lock_biometrics_enabled';
  static const String _prefTimeoutKey = 'zelon_lock_timeout';
  static const String _prefLastActiveKey = 'zelon_lock_last_active';

  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isLockEnabled = false;
  String? _pin;
  bool _isBiometricsEnabled = false;
  bool _canCheckBiometrics = false;
  int _timeoutMinutes = 0; // 0 = immediately
  bool _isUnlockedSession = false;

  bool get isLockEnabled => _isLockEnabled;
  bool get hasPin => _pin != null && _pin!.isNotEmpty;
  bool get isBiometricsEnabled => _isBiometricsEnabled;
  bool get canCheckBiometrics => _canCheckBiometrics;
  int get timeoutMinutes => _timeoutMinutes;
  bool get isUnlockedSession => _isUnlockedSession;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isLockEnabled = prefs.getBool(_prefLockEnabledKey) ?? false;
    _pin = prefs.getString(_prefPinKey);
    _isBiometricsEnabled = prefs.getBool(_prefBiometricsEnabledKey) ?? false;
    _timeoutMinutes = prefs.getInt(_prefTimeoutKey) ?? 0;

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      _canCheckBiometrics = canCheck || isSupported;
    } catch (_) {
      _canCheckBiometrics = false;
    }

    notifyListeners();
  }

  bool shouldPromptLock() {
    if (!_isLockEnabled) return false;
    if ((_pin == null || _pin!.isEmpty) && !_isBiometricsEnabled) return false;
    if (!_isUnlockedSession) return true;
    return false;
  }

  void onAppPaused() {
    if (_timeoutMinutes == 0) {
      _isUnlockedSession = false;
      notifyListeners();
    }
  }

  void onAppResumed() async {
    if (!_isLockEnabled) return;
    if (_timeoutMinutes > 0) {
      final prefs = await SharedPreferences.getInstance();
      final lastActive = prefs.getInt(_prefLastActiveKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastActive > _timeoutMinutes * 60 * 1000) {
        _isUnlockedSession = false;
        notifyListeners();
      }
    }
  }

  void recordActivity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefLastActiveKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> setPin(String newPin, {int timeoutMinutes = 0, bool enableBiometrics = true}) async {
    if (newPin.length < 4) return false;
    final prefs = await SharedPreferences.getInstance();
    _pin = newPin;
    _isLockEnabled = true;
    _timeoutMinutes = timeoutMinutes;
    _isBiometricsEnabled = enableBiometrics;
    _isUnlockedSession = true;

    await prefs.setString(_prefPinKey, newPin);
    await prefs.setBool(_prefLockEnabledKey, true);
    await prefs.setBool(_prefBiometricsEnabledKey, enableBiometrics);
    await prefs.setInt(_prefTimeoutKey, timeoutMinutes);
    notifyListeners();
    return true;
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _isBiometricsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBiometricsEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> disableLock() async {
    final prefs = await SharedPreferences.getInstance();
    _isLockEnabled = false;
    _pin = null;
    _isBiometricsEnabled = false;
    _isUnlockedSession = true;

    await prefs.setBool(_prefLockEnabledKey, false);
    await prefs.remove(_prefPinKey);
    await prefs.setBool(_prefBiometricsEnabledKey, false);
    notifyListeners();
  }

  Future<void> setTimeout(int minutes) async {
    _timeoutMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefTimeoutKey, minutes);
    notifyListeners();
  }

  bool verifyPin(String input) {
    if (_pin != null && _pin == input) {
      _isUnlockedSession = true;
      recordActivity();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> authenticateBiometrics() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan fingerprint to unlock Zelon Messenger',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (authenticated) {
        _isUnlockedSession = true;
        recordActivity();
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  void lockNow() {
    _isUnlockedSession = false;
    notifyListeners();
  }
}
