import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/instance.dart';

class CacheService {
  static const String _chatsPrefix = 'cache_chats_';
  static const String _messagesPrefix = 'cache_msgs_';
  static const String _instancesKey = 'cache_instances';

  static Future<void> saveInstances(List<InstanceModel> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString(_instancesKey, data);
    } catch (_) {}
  }

  static Future<List<InstanceModel>> getCachedInstances() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_instancesKey);
      if (str == null) return [];
      final list = jsonDecode(str) as List;
      return list.map((e) => InstanceModel.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveChats(String instanceId, List<ChatModel> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString('$_chatsPrefix$instanceId', data);
    } catch (_) {}
  }

  static Future<List<ChatModel>> getCachedChats(String instanceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('$_chatsPrefix$instanceId');
      if (str == null) return [];
      final list = jsonDecode(str) as List;
      return list.map((e) => ChatModel.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMessages(String instanceId, String chatId, List<MessageModel> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString('$_messagesPrefix${instanceId}_$chatId', data);
    } catch (_) {}
  }

  static Future<List<MessageModel>> getCachedMessages(String instanceId, String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('$_messagesPrefix${instanceId}_$chatId');
      if (str == null) return [];
      final list = jsonDecode(str) as List;
      return list.map((e) => MessageModel.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }
}
