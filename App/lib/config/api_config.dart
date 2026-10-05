import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String defaultBaseUrl = 'https://wa.hostzelon.com';
  static const String prefBaseUrlKey = 'zelon_base_url';

  static String _baseUrl = defaultBaseUrl;
  static String get baseUrl => _baseUrl;

  static Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(prefBaseUrlKey) ?? defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    var trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    _baseUrl = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefBaseUrlKey, _baseUrl);
  }

  // Endpoints
  static String get loginUrl => '$_baseUrl/api/login';
  static String get meUrl => '$_baseUrl/api/me';
  static String get logoutUrl => '$_baseUrl/api/logout';
  static String get instancesUrl => '$_baseUrl/api/instances';
  static String get adminUsersUrl => '$_baseUrl/api/admin/users';

  static String instanceUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId';
  static String connectUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/connect';
  static String qrUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/qr';
  static String pairingCodeUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/pairing-code';
  static String restartUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/restart';
  static String chatsUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/chats';
  static String chatMessagesUrl(String instanceId, String chatJid) =>
      '$_baseUrl/api/instances/$instanceId/chats/$chatJid/messages';
  static String chatPictureUrl(String instanceId, String chatJid, {bool hd = true}) =>
      '$_baseUrl/api/instances/$instanceId/chats/$chatJid/picture${hd ? "?full=1" : ""}';
  static String chatInfoUrl(String instanceId, String chatJid) =>
      '$_baseUrl/api/instances/$instanceId/chats/$chatJid/info';
  static String sendPresenceUrl(String instanceId, String chatJid) =>
      '$_baseUrl/api/instances/$instanceId/chats/$chatJid/presence';
  static String sendMessageUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/messages';
  static String statusesUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/statuses';
  static String campaignsUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/campaigns';
  static String rulesUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/rules';
  static String mediaUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/media';
}
