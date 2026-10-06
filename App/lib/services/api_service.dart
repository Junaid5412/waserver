import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/instance.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/status_model.dart';
import '../models/campaign.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class GeminiTestResult {
  final bool success;
  final String message;
  final List<String> availableModels;
  final String? activeModel;
  final int? statusCode;

  const GeminiTestResult({
    required this.success,
    required this.message,
    this.availableModels = const [],
    this.activeModel,
    this.statusCode,
  });
}

class ApiService {
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> _headers([Map<String, String>? extra]) {
    String originStr = ApiConfig.baseUrl;
    try {
      final uri = Uri.parse(ApiConfig.baseUrl);
      final portPart = (uri.hasPort && uri.port != 80 && uri.port != 443) ? ':${uri.port}' : '';
      originStr = '${uri.scheme}://${uri.host}$portPart';
    } catch (_) {}

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Origin': originStr,
      'Referer': '$originStr/',
      'X-Requested-With': 'com.zelon.messenger',
    };
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
      headers['Cookie'] = 'zelon_session=$_token';
      headers['X-Session-Token'] = _token!;
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Map<String, String> get authHeaders => _headers();

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      Uri.parse(ApiConfig.loginUrl),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Sign in failed');
    }
    // Also parse cookie if returned
    final rawCookie = res.headers['set-cookie'];
    if (rawCookie != null) {
      final m = RegExp(r'zelon_session=([^;]+)').firstMatch(rawCookie);
      if (m != null && (data['token'] == null || data['token'].toString().isEmpty)) {
        data['token'] = m.group(1);
      }
    }
    return Map<String, dynamic>.from(data);
  }

  Future<UserModel> getMe() async {
    final res = await http.get(Uri.parse(ApiConfig.meUrl), headers: _headers());
    if (res.statusCode != 200) throw Exception('Failed to get user profile');
    return UserModel.fromJson(jsonDecode(res.body));
  }

  Future<void> logout() async {
    try {
      await http.post(Uri.parse(ApiConfig.logoutUrl), headers: _headers());
    } catch (_) {}
  }

  Future<List<InstanceModel>> getInstances() async {
    final res = await http.get(Uri.parse(ApiConfig.instancesUrl), headers: _headers());
    if (res.statusCode != 200) throw Exception('Failed to load instances');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => InstanceModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<InstanceModel> createInstance(String name) async {
    final res = await http.post(
      Uri.parse(ApiConfig.instancesUrl),
      headers: _headers(),
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to create instance');
    }
    return InstanceModel.fromJson(jsonDecode(res.body));
  }

  Future<void> deleteInstance(String instanceId) async {
    final res = await http.post(
      Uri.parse(ApiConfig.deleteInstanceUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to delete account');
    }
  }

  Future<void> connectInstance(String instanceId) async {
    final res = await http.post(
      Uri.parse(ApiConfig.connectUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) throw Exception('Failed to start connection');
  }

  Future<String?> getQrCode(String instanceId) async {
    final res = await http.get(
      Uri.parse(ApiConfig.qrUrl(instanceId)),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['qr']?.toString();
    }
    return null;
  }

  Future<String> requestPairingCode(String instanceId, String phone) async {
    final res = await http.post(
      Uri.parse(ApiConfig.pairingCodeUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode({'phone': phone}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Pairing code request failed');
    return data['code']?.toString() ?? '';
  }

  Future<void> restartInstance(String instanceId) async {
    final res = await http.post(
      Uri.parse(ApiConfig.restartUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) throw Exception('Failed to restart instance');
  }

  Future<List<ChatModel>> getChats(String instanceId, {String? search}) async {
    var url = ApiConfig.chatsUrl(instanceId);
    if (search != null && search.isNotEmpty) {
      url += '?search=${Uri.encodeComponent(search)}';
    }
    final res = await http.get(Uri.parse(url), headers: _headers());
    if (res.statusCode != 200) throw Exception('Failed to load chats');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => ChatModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<MessageModel>> getMessages(String instanceId, String chatJid, {int limit = 50}) async {
    final url = '${ApiConfig.chatMessagesUrl(instanceId, chatJid)}?limit=$limit';
    final res = await http.get(Uri.parse(url), headers: _headers());
    if (res.statusCode != 200) throw Exception('Failed to load messages');
    final list = jsonDecode(res.body) as List;
    final msgs = list.map((e) => MessageModel.fromJson(Map<String, dynamic>.from(e))).toList();
    // Return oldest to newest for chat view
    return msgs.reversed.toList();
  }

  Future<void> sendMessage(String instanceId, {
    required String to,
    String? text,
    String type = 'text',
    String? quotedWaId,
  }) async {
    final body = <String, dynamic>{
      'to': to,
      'type': type,
    };
    if (text != null) body['text'] = text;
    if (quotedWaId != null) body['quotedId'] = quotedWaId;

    final res = await http.post(
      Uri.parse(ApiConfig.sendMessageUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 202) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to send message');
    }
  }

  Future<List<StatusModel>> getStatuses(String instanceId) async {
    final res = await http.get(Uri.parse(ApiConfig.statusesUrl(instanceId)), headers: _headers());
    if (res.statusCode != 200) throw Exception('Failed to load statuses');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => StatusModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> postStatus(String instanceId, String text, List<String> audience) async {
    final res = await http.post(
      Uri.parse(ApiConfig.statusesUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode({
        'type': 'text',
        'text': text,
        'statusAudience': audience,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 202) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to post status');
    }
  }

  Future<List<CampaignModel>> getCampaigns(String instanceId) async {
    final res = await http.get(Uri.parse(ApiConfig.campaignsUrl(instanceId)), headers: _headers());
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body) as List;
    return list.map((e) => CampaignModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<UserModel>> getAdminUsers() async {
    final res = await http.get(Uri.parse(ApiConfig.adminUsersUrl), headers: _headers());
    if (res.statusCode != 200) throw Exception('Admin access required');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => UserModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> updateAdminUser(String userId, {
    String? name,
    String? email,
    String? role,
    bool? disabled,
    Map<String, dynamic>? permissions,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (role != null) body['role'] = role;
    if (disabled != null) body['disabled'] = disabled;
    if (permissions != null) body['permissions'] = permissions;

    final res = await http.put(
      Uri.parse('${ApiConfig.adminUsersUrl}/$userId'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to update user');
    }
  }

  Future<Map<String, dynamic>> createAdminUser({
    required String email,
    String? name,
    String role = 'user',
    Map<String, dynamic>? permissions,
  }) async {
    final body = <String, dynamic>{
      'email': email.trim().toLowerCase(),
      'role': role,
    };
    if (name != null && name.trim().isNotEmpty) body['name'] = name.trim();
    if (permissions != null) body['permissions'] = permissions;

    final res = await http.post(
      Uri.parse(ApiConfig.adminUsersUrl),
      headers: _headers(),
      body: jsonEncode(body),
    );
    final d = jsonDecode(res.body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(d['error'] ?? 'Failed to create user');
    }
    return Map<String, dynamic>.from(d);
  }

  Future<void> deleteAdminUser(String userId) async {
    final res = await http.delete(
      Uri.parse('${ApiConfig.adminUsersUrl}/$userId'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to delete user');
    }
  }

  Future<String> resetAdminUserPassword(String userId) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.adminUsersUrl}/$userId/reset-password'),
      headers: _headers(),
    );
    final d = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(d['error'] ?? 'Failed to reset password');
    }
    return d['password']?.toString() ?? '';
  }

  Future<void> signOutAdminUser(String userId) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.adminUsersUrl}/$userId/sign-out'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to sign out user');
    }
  }

  Future<Map<String, dynamic>> getAdminSystemHealth() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/admin/system'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load server health status');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  Future<void> triggerKeepAlive() async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/admin/keepalive/run'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to trigger keepalive');
    }
  }

  Future<Map<String, dynamic>> getAccountProfile() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/account'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch account profile');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  Future<void> updateAccountProfile({required String name}) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/api/account/profile'),
      headers: _headers(),
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to update profile');
    }
  }

  Future<void> updateAccountPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/account/password'),
      headers: _headers(),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to update password');
    }
  }

  Future<void> reactMessage(String instanceId, String waId, String emoji) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/inbox/$waId/reaction'),
      headers: _headers(),
      body: jsonEncode({'emoji': emoji}),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to react to message');
    }
  }

  Future<void> starMessage(String instanceId, String waId, bool star) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/inbox/$waId/star'),
      headers: _headers(),
      body: jsonEncode({'star': star}),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to star message');
    }
  }

  Future<void> deleteMessage(String instanceId, String waId, {String scope = 'everyone'}) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/inbox/$waId/delete'),
      headers: _headers(),
      body: jsonEncode({'scope': scope}),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to delete message');
    }
  }

  Future<void> markChatAsRead(String instanceId, String chatJid) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/chats/${Uri.encodeComponent(chatJid)}/settings'),
      headers: _headers(),
      body: jsonEncode({'read': true}),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to mark chat as read');
    }
  }

  Future<void> subscribePresence(String instanceId, String chatJid) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/chats/${Uri.encodeComponent(chatJid)}/subscribe'),
        headers: _headers(),
        body: jsonEncode({}),
      );
    } catch (_) {}
  }

  Future<void> sendPresence(String instanceId, String chatJid, String presence) async {
    try {
      await http.post(
        Uri.parse(ApiConfig.sendPresenceUrl(instanceId, chatJid)),
        headers: _headers(),
        body: jsonEncode({'presence': presence}),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getChatInfo(String instanceId, String chatJid) async {
    try {
      final res = await http.get(
        Uri.parse(ApiConfig.chatInfoUrl(instanceId, chatJid)),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  Future<void> sendMediaMessage(String instanceId, {
    required String to,
    required String type,
    required String base64Data,
    String? filename,
    String? mimetype,
    String? caption,
    String? quotedWaId,
    bool ptt = false,
  }) async {
    final body = <String, dynamic>{
      'to': to,
      'type': type,
      'data': base64Data,
    };
    if (filename != null && filename.isNotEmpty) body['filename'] = filename;
    if (mimetype != null && mimetype.isNotEmpty) body['mimetype'] = mimetype;
    if (caption != null && caption.isNotEmpty) body['text'] = caption;
    if (quotedWaId != null && quotedWaId.isNotEmpty) body['quotedId'] = quotedWaId;
    if (ptt) body['ptt'] = ptt;

    final res = await http.post(
      Uri.parse(ApiConfig.sendMessageUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 202) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to send media');
    }
  }

  Future<void> markMessageAsRead(String instanceId, String waId) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/inbox/${Uri.encodeComponent(waId)}/read'),
      headers: _headers(),
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to mark message as read');
    }
  }

  Future<void> editMessageText(String instanceId, String waId, String newText) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/inbox/${Uri.encodeComponent(waId)}/text'),
      headers: _headers(),
      body: jsonEncode({'text': newText}),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to edit message');
    }
  }

  Future<void> forwardMessage(String instanceId, {required String to, required String forwardWaId}) async {
    final res = await http.post(
      Uri.parse(ApiConfig.sendMessageUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode({
        'to': to,
        'type': 'forward',
        'forwardId': forwardWaId,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 202) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to forward message');
    }
  }

  Future<void> sendLocationMessage(String instanceId, {
    required String to,
    required double latitude,
    required double longitude,
    String? name,
    String? address,
    String? quotedWaId,
  }) async {
    final body = <String, dynamic>{
      'to': to,
      'type': 'location',
      'latitude': latitude,
      'longitude': longitude,
    };
    if (name != null && name.trim().isNotEmpty) {
      final trimmed = name.trim();
      body['name'] = trimmed.length > 90 ? trimmed.substring(0, 90) : trimmed;
    }
    if (address != null && address.trim().isNotEmpty) {
      final trimmed = address.trim();
      body['address'] = trimmed.length > 250 ? trimmed.substring(0, 250) : trimmed;
    }
    if (quotedWaId != null && quotedWaId.isNotEmpty) body['quotedId'] = quotedWaId;

    final res = await http.post(
      Uri.parse(ApiConfig.sendMessageUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 202) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to send location');
    }
  }

  Future<void> sendContactMessage(String instanceId, {
    required String to,
    required String name,
    required String phone,
    String? quotedWaId,
  }) async {
    final body = <String, dynamic>{
      'to': to,
      'type': 'contact',
      'name': name,
      'phone': phone,
    };
    if (quotedWaId != null && quotedWaId.isNotEmpty) body['quotedId'] = quotedWaId;

    final res = await http.post(
      Uri.parse(ApiConfig.sendMessageUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 202) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to send contact');
    }
  }

  Future<void> sendPollMessage(String instanceId, {
    required String to,
    required String question,
    required List<String> options,
    int selectableCount = 1,
    String? quotedWaId,
  }) async {
    final body = <String, dynamic>{
      'to': to,
      'type': 'poll',
      'text': question,
      'options': options,
      'selectableCount': selectableCount,
    };
    if (quotedWaId != null && quotedWaId.isNotEmpty) body['quotedId'] = quotedWaId;

    final res = await http.post(
      Uri.parse(ApiConfig.sendMessageUrl(instanceId)),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 202) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to send poll');
    }
  }

  static const List<String> supportedGeminiModels = [
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.1-pro',
    'gemini-2.5-pro',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-1.5-pro',
    'gemini-1.5-flash',
  ];
  static const String defaultGeminiModel = 'gemini-2.5-flash';
  static const String _prefGeminiKeys = 'zelon_gemini_keys';
  static const String _prefGeminiModel = 'zelon_gemini_model';

  Future<Map<String, dynamic>> getAdminGeminiData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> localKeys = prefs.getStringList(_prefGeminiKeys) ?? [];
    String localModel = prefs.getString(_prefGeminiModel) ?? defaultGeminiModel;

    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/gemini'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final serverKeys = List<String>.from(data['keys'] ?? []);
        final mergedKeys = {...localKeys, ...serverKeys}.toList();
        final serverModel = data['model']?.toString() ?? localModel;
        await prefs.setStringList(_prefGeminiKeys, mergedKeys);
        await prefs.setString(_prefGeminiModel, serverModel);
        return {
          'keys': mergedKeys,
          'model': serverModel,
          'supportedModels': supportedGeminiModels,
        };
      }
    } catch (_) {}

    return {
      'keys': localKeys,
      'model': localModel,
      'supportedModels': supportedGeminiModels,
    };
  }

  Future<List<String>> getAdminGeminiKeys() async {
    final data = await getAdminGeminiData();
    return List<String>.from(data['keys'] ?? []);
  }

  Future<void> addAdminGeminiKey(String apiKey) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return;

    // 1. Immediately persist locally so it always works
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList(_prefGeminiKeys) ?? [];
    if (!keys.contains(cleanKey)) {
      keys.add(cleanKey);
      await prefs.setStringList(_prefGeminiKeys, keys);
    }

    // 2. Synchronize to server (catch any endpoint errors gracefully)
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/gemini'),
        headers: _headers(),
        body: jsonEncode({'key': cleanKey}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> setAdminGeminiModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefGeminiModel, model);

    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/gemini'),
        headers: _headers(),
        body: jsonEncode({'model': model}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> deleteAdminGeminiKey(String apiKey) async {
    final cleanKey = apiKey.trim();

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList(_prefGeminiKeys) ?? [];
    keys.remove(cleanKey);
    await prefs.setStringList(_prefGeminiKeys, keys);

    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/gemini/delete'),
        headers: _headers(),
        body: jsonEncode({'key': cleanKey}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> removeAdminGeminiKey(String apiKey) => deleteAdminGeminiKey(apiKey);

  Future<GeminiTestResult> testGeminiKey(String apiKey, {String? model}) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return const GeminiTestResult(
        success: false,
        message: 'API Key cannot be empty',
      );
    }

    // Step 1: Direct verification with Google Generative Language models.list API
    // This tests key validity and project access WITHOUT consuming quota or relying on hardcoded model IDs.
    try {
      final listUrl = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$cleanKey');
      final res = await http.get(listUrl).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data['models'] as List<dynamic>? ?? [];
        final availableModels = <String>[];
        for (final item in rawList) {
          if (item is Map) {
            final name = item['name']?.toString().replaceFirst('models/', '') ?? '';
            final methods = item['supportedGenerationMethods'] as List<dynamic>? ?? [];
            if (name.isNotEmpty && (methods.isEmpty || methods.contains('generateContent'))) {
              availableModels.add(name);
            }
          }
        }

        // Test generation ping on confirmed available model or default fallback
        final pingModel = (model != null && availableModels.contains(model))
            ? model
            : (availableModels.contains('gemini-2.0-flash')
                ? 'gemini-2.0-flash'
                : (availableModels.contains('gemini-1.5-flash')
                    ? 'gemini-1.5-flash'
                    : (availableModels.isNotEmpty ? availableModels.first : 'gemini-2.0-flash')));

        try {
          final pingUrl = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$pingModel:generateContent?key=$cleanKey');
          final pingRes = await http.post(
            pingUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [{'text': 'ping'}]
                }
              ]
            }),
          ).timeout(const Duration(seconds: 8));

          if (pingRes.statusCode == 200) {
            return GeminiTestResult(
              success: true,
              message: 'Verified & Active with Google (${availableModels.length} models available)',
              availableModels: availableModels,
              activeModel: pingModel,
              statusCode: 200,
            );
          } else {
            final pingData = jsonDecode(pingRes.body);
            final pingErr = pingData['error']?['message']?.toString();
            if (pingRes.statusCode == 429) {
              return GeminiTestResult(
                success: false,
                message: 'Key is valid, but rate limited or quota exhausted: ${pingErr ?? "429 Too Many Requests"}',
                availableModels: availableModels,
                statusCode: 429,
              );
            }
            return GeminiTestResult(
              success: true,
              message: 'Verified & Active with Google (${availableModels.length} models available)',
              availableModels: availableModels,
              activeModel: pingModel,
              statusCode: 200,
            );
          }
        } catch (_) {
          return GeminiTestResult(
            success: true,
            message: 'Verified & Active with Google (${availableModels.length} models available)',
            availableModels: availableModels,
            activeModel: pingModel,
            statusCode: 200,
          );
        }
      } else {
        // Parse Google's exact error message
        String errMsg = 'HTTP ${res.statusCode}';
        try {
          final errData = jsonDecode(res.body);
          errMsg = errData['error']?['message']?.toString() ?? errMsg;
        } catch (_) {}

        return GeminiTestResult(
          success: false,
          message: 'Google Verification Error (${res.statusCode}): $errMsg',
          statusCode: res.statusCode,
        );
      }
    } catch (clientErr) {
      // Step 2: Fallback to server-side verification if client couldn't reach Google directly
      try {
        final serverRes = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/api/admin/gemini/test'),
          headers: _headers(),
          body: jsonEncode({'key': cleanKey, 'model': model}),
        ).timeout(const Duration(seconds: 10));

        if (serverRes.statusCode == 200) {
          final serverData = jsonDecode(serverRes.body);
          final ok = serverData['ok'] == true;
          final msg = serverData['message']?.toString() ?? (ok ? 'Verified with Google' : 'Verification failed');
          final models = (serverData['availableModels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          return GeminiTestResult(
            success: ok,
            message: msg,
            availableModels: models,
            activeModel: serverData['activeModel']?.toString(),
            statusCode: ok ? 200 : (serverData['code'] as int? ?? 400),
          );
        }
      } catch (_) {}

      return GeminiTestResult(
        success: false,
        message: 'Connection failed: ${clientErr.toString().replaceAll("Exception: ", "")}',
      );
    }
  }

  Future<List<String>> generateSmartReply(
    String instanceId,
    String chatJid,
    List<MessageModel> recentMessages, {
    String? prompt,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var keys = prefs.getStringList(_prefGeminiKeys) ?? [];

    // Auto-sync keys from server if local list is empty
    if (keys.isEmpty) {
      try {
        final serverData = await getAdminGeminiData();
        keys = List<String>.from(serverData['keys'] ?? []);
        if (keys.isNotEmpty) {
          await prefs.setStringList(_prefGeminiKeys, keys);
        }
      } catch (_) {}
    }

    // 1. Try server endpoint first
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/ai/suggest-reply'),
        headers: _headers(),
        body: jsonEncode({
          'chatJid': chatJid,
          'messages': recentMessages.map((m) => {
            'text': m.text,
            'fromMe': m.fromMe,
            'type': m.type,
          }).toList(),
          'prompt': prompt,
          'model': model,
          'keys': keys,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<String>.from(data['suggestions'] ?? []);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 2. Resilient Direct Client-side failover with multi-key rotation and all latest models
    return await _callClientGeminiSmartReply(recentMessages, prompt: prompt, model: model);
  }

  Future<List<String>> _callClientGeminiSmartReply(
    List<MessageModel> recentMessages, {
    String? prompt,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var keys = prefs.getStringList(_prefGeminiKeys) ?? [];
    if (keys.isEmpty) {
      try {
        final serverData = await getAdminGeminiData();
        keys = List<String>.from(serverData['keys'] ?? []);
        if (keys.isNotEmpty) {
          await prefs.setStringList(_prefGeminiKeys, keys);
        }
      } catch (_) {}
    }

    if (keys.isEmpty) {
      throw Exception('No Gemini API keys configured. Please add an API key in Admin Control Center -> Gemini AI.');
    }

    final selectedModel = model ?? prefs.getString(_prefGeminiModel) ?? defaultGeminiModel;
    final fallbackModels = [
      selectedModel,
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-2.0-flash-lite',
      'gemini-1.5-pro',
      'gemini-2.5-flash',
    ].toSet().toList();

    final transcript = recentMessages.take(20).map((m) {
      final sender = m.fromMe ? 'Me' : 'Contact';
      final text = m.text.isNotEmpty ? m.text : (m.type == 'image' ? '[Image]' : '[Voice note]');
      return '$sender: $text';
    }).join('\n');

    const systemPrompt = 'You are a smart WhatsApp reply assistant. Based on recent messages, suggest 3 short, natural, polite replies for Me. Match the conversation language. Return STRICTLY as a raw JSON array of 3 strings: ["reply1", "reply2", "reply3"].';
    final userQuery = prompt != null && prompt.trim().isNotEmpty
        ? (transcript.isNotEmpty
            ? 'Transcript:\n$transcript\n\nUser intent: "$prompt". Provide 3 reply variations as JSON array.'
            : 'User intent: "$prompt". Provide 3 reply variations for WhatsApp chat as JSON array.')
        : (transcript.isNotEmpty
            ? 'Transcript:\n$transcript\n\nProvide 3 suggested replies for Me as a JSON array.'
            : 'Provide 3 friendly, polite general starter replies for Me as a JSON array.');

    String lastError = 'Unable to generate reply with available Gemini keys';

    for (int k = 0; k < keys.length; k++) {
      final key = keys[k].trim();
      if (key.isEmpty) continue;

      for (int m = 0; m < fallbackModels.length; m++) {
        final currentModel = fallbackModels[m];
        try {
          final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$currentModel:generateContent?key=$key',
          );
          final res = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': '$systemPrompt\n\n$userQuery'}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.7,
                'maxOutputTokens': 500,
              }
            }),
          ).timeout(const Duration(seconds: 15));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final candidates = data['candidates'] as List<dynamic>? ?? [];
            if (candidates.isNotEmpty) {
              final content = candidates[0]['content'];
              final parts = content?['parts'] as List<dynamic>? ?? [];
              final textParts = <String>[];
              for (final p in parts) {
                if (p is Map && p['text'] != null) {
                  final t = p['text'].toString().trim();
                  if ((p['thought'] != true || parts.length == 1) && t.isNotEmpty) {
                    textParts.add(t);
                  }
                }
              }
              final fullText = textParts.join('\n').trim();
              if (fullText.isNotEmpty) {
                final suggestions = _parseReplySuggestions(fullText);
                if (suggestions.isNotEmpty) return suggestions;
                final lines = fullText
                    .split(RegExp(r'[\r\n]+'))
                    .map((l) => l.replaceAll(RegExp(r'^[\d\.\-\*"\s]+'), '').replaceAll(RegExp(r'["\s]+$'), '').trim())
                    .where((l) => l.isNotEmpty && !l.startsWith('{') && !l.startsWith('['))
                    .take(3)
                    .toList();
                if (lines.isNotEmpty) return lines;
                return [fullText];
              }
            }
          } else {
            String errMsg = 'HTTP ${res.statusCode}';
            try {
              final errJson = jsonDecode(res.body);
              errMsg = errJson['error']?['message']?.toString() ?? errMsg;
            } catch (_) {}

            if (res.statusCode == 404) {
              lastError = 'Model $currentModel not supported for this key: $errMsg';
              continue; // try next model
            } else if (res.statusCode == 429) {
              lastError = 'Key #${k + 1} quota exhausted: $errMsg';
              break; // rotate to next key
            } else {
              lastError = 'Key #${k + 1} Google error (${res.statusCode}): $errMsg';
              break; // rotate to next key
            }
          }
        } catch (e) {
          lastError = 'Network/timeout error: ${e.toString().replaceAll("Exception: ", "")}';
        }
      }
    }
    throw Exception(lastError);
  }

  List<String> _parseReplySuggestions(String raw) {
    var text = raw.trim();
    if (text.startsWith('```json')) {
      text = text.replaceFirst(RegExp(r'^```json\s*'), '').replaceFirst(RegExp(r'\s*```$'), '');
    } else if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```\s*'), '').replaceFirst(RegExp(r'\s*```$'), '');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).take(3).toList();
      }
    } catch (_) {}

    // Fallback: extract array from inside string if wrapped in brackets
    final arrayMatch = RegExp(r'\[\s*(".*?")\s*\]', dotAll: true).firstMatch(text);
    if (arrayMatch != null) {
      try {
        final decoded = jsonDecode(arrayMatch.group(0)!);
        if (decoded is List) {
          return decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).take(3).toList();
        }
      } catch (_) {}
    }

    return text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.replaceAll(RegExp(r'^[\d\.\-\*"\s]+'), '').replaceAll(RegExp(r'["\s]+$'), '').trim())
        .where((l) => l.isNotEmpty && !l.startsWith('{') && !l.startsWith('['))
        .take(3)
        .toList();
  }

  // Admin Broadcasts
  Future<List<Map<String, dynamic>>> getAdminBroadcasts() async {
    final res = await http.get(Uri.parse(ApiConfig.adminBroadcastsUrl), headers: _headers());
    if (res.statusCode != 200) throw Exception('Failed to load broadcasts');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createAdminBroadcast({
    required String title,
    required String body,
    bool requireAck = true,
    bool allowReply = true,
    String urgency = 'normal',
  }) async {
    final res = await http.post(
      Uri.parse(ApiConfig.adminBroadcastsUrl),
      headers: _headers(),
      body: jsonEncode({
        'title': title,
        'body': body,
        'requireAck': requireAck,
        'allowReply': allowReply,
        'urgency': urgency,
      }),
    );
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      throw Exception(d['error'] ?? 'Failed to send broadcast');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  Future<Map<String, dynamic>> getBroadcastAudit(String broadcastId) async {
    final res = await http.get(Uri.parse(ApiConfig.adminBroadcastAuditUrl(broadcastId)), headers: _headers());
    if (res.statusCode != 200) throw Exception('Failed to load audit data');
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  // User Broadcasts
  Future<List<Map<String, dynamic>>> getUserBroadcasts() async {
    final res = await http.get(Uri.parse(ApiConfig.userBroadcastsUrl), headers: _headers());
    if (res.statusCode != 200) throw Exception('Failed to load announcements');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> markBroadcastSeen(String broadcastId) async {
    try {
      await http.post(Uri.parse(ApiConfig.broadcastSeenUrl(broadcastId)), headers: _headers(), body: jsonEncode({}));
    } catch (_) {}
  }

  Future<void> acknowledgeBroadcast(String broadcastId) async {
    final res = await http.post(
      Uri.parse(ApiConfig.broadcastAckUrl(broadcastId)),
      headers: _headers(),
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) throw Exception('Failed to acknowledge message');
  }

  Future<void> replyToBroadcast(String broadcastId, String reply) async {
    final res = await http.post(
      Uri.parse(ApiConfig.broadcastReplyUrl(broadcastId)),
      headers: _headers(),
      body: jsonEncode({'reply': reply}),
    );
    if (res.statusCode != 200) throw Exception('Failed to send reply');
  }
}


