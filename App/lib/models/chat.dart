class ChatModel {
  final String chatId;
  final String name;
  final String? phone;
  final String lastPreview;
  final String? lastMessageId;
  final int unread;
  final DateTime? createdAt;
  final bool pinned;
  final bool archived;

  ChatModel({
    required this.chatId,
    required this.name,
    this.phone,
    this.lastPreview = '',
    this.lastMessageId,
    this.unread = 0,
    this.createdAt,
    this.pinned = false,
    this.archived = false,
  });

  bool get isGroup => chatId.endsWith('@g.us');
  bool get isStatus => chatId == 'status@broadcast';

  String get displayTitle {
    if (name.isNotEmpty && name != chatId) return name;
    if (phone != null && phone!.isNotEmpty) return phone!;
    if (isGroup) return 'WhatsApp Group';
    final user = chatId.split('@')[0];
    return user.isNotEmpty ? '+$user' : chatId;
  }

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    if (json['createdAt'] != null) {
      dt = DateTime.tryParse(json['createdAt'].toString());
    }
    return ChatModel(
      chatId: json['chatId']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      lastPreview: json['lastPreview']?.toString() ?? '',
      lastMessageId: json['lastMessageId']?.toString(),
      unread: (json['unread'] is num) ? (json['unread'] as num).toInt() : 0,
      createdAt: dt,
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chatId': chatId,
      'name': name,
      'phone': phone,
      'lastPreview': lastPreview,
      'lastMessageId': lastMessageId,
      'unread': unread,
      'createdAt': createdAt?.toIso8601String(),
      'pinned': pinned,
      'archived': archived,
    };
  }
}
