import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/instance.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/status_model.dart';
import '../models/campaign.dart';
import '../models/user.dart';

class ApiService {
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> _headers([Map<String, String>? extra]) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
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
    if (quotedWaId != null) body['quoted'] = quotedWaId;

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
}
