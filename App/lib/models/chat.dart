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
  final String kind;
  final bool isCommunityFlag;
  final bool isChannelFlag;
  final int participantsCount;

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
    this.kind = 'contact',
    this.isCommunityFlag = false,
    this.isChannelFlag = false,
    this.participantsCount = 0,
  });

  bool get isChannel =>
      isChannelFlag ||
      kind == 'channel' ||
      kind == 'newsletter' ||
      chatId.endsWith('@newsletter');

  bool get isCommunity =>
      isCommunityFlag ||
      kind == 'community' ||
      chatId.contains('@community') ||
      (!isChannel && name.toLowerCase().contains('community'));

  bool get isGroup =>
      !isChannel && !isCommunity && !isStatus && (kind == 'group' || chatId.endsWith('@g.us'));

  bool get isStatus =>
      chatId == 'status@broadcast' || kind == 'broadcast' || chatId.endsWith('@broadcast');

  bool get isDirect =>
      !isGroup && !isChannel && !isCommunity && !isStatus;

  int get unreadCount => unread;

  String get displayTitle {
    if (name.isNotEmpty && name != chatId) return name;
    if (phone != null && phone!.isNotEmpty) return phone!;
    if (isChannel) return 'Channel';
    if (isCommunity) return 'Community';
    if (isGroup) return 'Group Chat';
    final user = chatId.split('@')[0];
    return user.isNotEmpty ? '+$user' : chatId;
  }

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    if (json['createdAt'] != null) {
      dt = DateTime.tryParse(json['createdAt'].toString());
    }
    final rawKind = json['kind']?.toString().toLowerCase() ?? '';
    final rawChatId = json['chatId']?.toString() ?? json['id']?.toString() ?? '';
    final rawName = json['name']?.toString() ?? '';
    final isComm = json['isCommunity'] == true ||
        rawKind == 'community' ||
        rawChatId.contains('@community') ||
        rawName.toLowerCase().contains('community');
    final isChan = json['isChannel'] == true ||
        rawKind == 'channel' ||
        rawKind == 'newsletter' ||
        rawChatId.endsWith('@newsletter');
    final parts = (json['participants'] is num) ? (json['participants'] as num).toInt() : 0;

    return ChatModel(
      chatId: rawChatId,
      name: rawName,
      phone: json['phone']?.toString(),
      lastPreview: json['lastPreview']?.toString() ?? '',
      lastMessageId: json['lastMessageId']?.toString(),
      unread: (json['unread'] is num) ? (json['unread'] as num).toInt() : 0,
      createdAt: dt,
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
      kind: rawKind,
      isCommunityFlag: isComm,
      isChannelFlag: isChan,
      participantsCount: parts,
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
      'kind': kind,
      'isCommunity': isCommunity,
      'isChannel': isChannel,
      'participants': participantsCount,
    };
  }
}
