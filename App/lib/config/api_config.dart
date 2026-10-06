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
  static String get mediaUrl => '$_baseUrl/api/media';
  static String deleteInstanceUrl(String instanceId) => '$_baseUrl/api/instances/$instanceId/delete';

  // Admin Broadcasts & User Announcements
  static String get adminBroadcastsUrl => '$_baseUrl/api/admin/broadcasts';
  static String adminBroadcastAuditUrl(String id) => '$_baseUrl/api/admin/broadcasts/$id/audit';
  static String get userBroadcastsUrl => '$_baseUrl/api/user/broadcasts';
  static String broadcastSeenUrl(String id) => '$_baseUrl/api/user/broadcasts/$id/seen';
  static String broadcastAckUrl(String id) => '$_baseUrl/api/user/broadcasts/$id/ack';
  static String broadcastReplyUrl(String id) => '$_baseUrl/api/user/broadcasts/$id/reply';

  // Business Email Suite Endpoints
  static String get emailAccountsUrl => '$_baseUrl/api/email/accounts';
  static String get emailTestUrl => '$_baseUrl/api/email/accounts/test';
  static String emailAccountDeleteUrl(String id) => '$_baseUrl/api/email/accounts/$id';
  static String get emailFoldersUrl => '$_baseUrl/api/email/folders';
  static String get emailMessagesUrl => '$_baseUrl/api/email/messages';
  static String emailMessageDetailUrl(String uid) => '$_baseUrl/api/email/messages/$uid';
  static String emailAttachmentUrl(String uid, int index) => '$_baseUrl/api/email/messages/$uid/attachment/$index';
  static String get emailSendUrl => '$_baseUrl/api/email/send';
  static String emailFlagUrl(String uid) => '$_baseUrl/api/email/messages/$uid/flag';
  static String emailDeleteUrl(String uid) => '$_baseUrl/api/email/messages/$uid';
  static String get emailAiReplyUrl => '$_baseUrl/api/email/ai/reply';
}
