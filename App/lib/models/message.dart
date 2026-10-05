class MessageEditHistory {
  final String text;
  final DateTime? at;

  MessageEditHistory({required this.text, this.at});

  factory MessageEditHistory.fromJson(Map<String, dynamic> json) {
    return MessageEditHistory(
      text: json['text']?.toString() ?? '',
      at: json['at'] != null ? DateTime.tryParse(json['at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'at': at?.toIso8601String(),
  };
}

class MessageModel {
  final String id;
  final String waId;
  final String chatId;
  final bool fromMe;
  final String status;
  final String type;
  final String text;
  final DateTime? createdAt;
  final String participant;
  final String name;
  final bool deleted;
  final DateTime? deletedAt;
  final bool edited;
  final DateTime? editedAt;
  final String? originalText;
  final List<MessageEditHistory> edits;
  final Map<String, String> reactions;
  final String quotedText;
  final String? mimetype;
  final String? filename;
  final bool starred;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? locationAddress;

  String get senderName => name;
  String get senderJid => participant;
  bool get hasMedia =>
      type != 'text' &&
      type != 'deleted' &&
      type != 'location' &&
      type != 'contact' &&
      type != 'poll' &&
      ((mimetype != null && mimetype!.isNotEmpty && mimetype != 'text/plain') ||
          ['image', 'video', 'document', 'audio', 'sticker'].contains(type));
  bool get isLocation =>
      type == 'location' || (latitude != null && longitude != null);

  MessageModel({
    required this.id,
    required this.waId,
    required this.chatId,
    required this.fromMe,
    required this.status,
    required this.type,
    required this.text,
    this.createdAt,
    this.participant = '',
    this.name = '',
    this.deleted = false,
    this.deletedAt,
    this.edited = false,
    this.editedAt,
    this.originalText,
    this.edits = const [],
    this.reactions = const {},
    this.quotedText = '',
    this.mimetype,
    this.filename,
    this.starred = false,
    this.latitude,
    this.longitude,
    this.locationName,
    this.locationAddress,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    List<MessageEditHistory> history = [];
    if (json['edits'] is List) {
      for (final item in json['edits']) {
        if (item is Map) {
          history.add(MessageEditHistory.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    Map<String, String> reacts = {};
    if (json['reactions'] is Map) {
      json['reactions'].forEach((k, v) {
        if (v != null) reacts[k.toString()] = v.toString();
      });
    }

    double? lat;
    double? lng;
    String? locName;
    String? locAddr;
    double? parseCoord(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    if (json['location'] is Map) {
      final loc = json['location'] as Map;
      lat = parseCoord(loc['latitude']);
      lng = parseCoord(loc['longitude']);
      locName = loc['name']?.toString();
      locAddr = loc['address']?.toString();
    } else {
      lat = parseCoord(json['latitude']);
      lng = parseCoord(json['longitude']);
      locName = json['locationName']?.toString();
      locAddr = json['locationAddress']?.toString();
    }

    return MessageModel(
      id: json['id']?.toString() ?? '',
      waId: json['waId']?.toString() ?? json['id']?.toString() ?? '',
      chatId: json['chatId']?.toString() ?? '',
      fromMe: json['fromMe'] == true,
      status: json['status']?.toString() ?? 'received',
      type: json['type']?.toString() ?? 'text',
      text: json['text']?.toString() ?? '',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      participant: json['participant']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      deleted: json['deleted'] == true,
      deletedAt: json['deletedAt'] != null ? DateTime.tryParse(json['deletedAt'].toString()) : null,
      edited: json['edited'] == true,
      editedAt: json['editedAt'] != null ? DateTime.tryParse(json['editedAt'].toString()) : null,
      originalText: json['originalText']?.toString(),
      edits: history,
      reactions: reacts,
      quotedText: json['quotedText']?.toString() ?? '',
      mimetype: json['mimetype']?.toString(),
      filename: json['filename']?.toString(),
      starred: json['starred'] == true,
      latitude: lat,
      longitude: lng,
      locationName: locName,
      locationAddress: locAddr,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'waId': waId,
      'chatId': chatId,
      'fromMe': fromMe,
      'status': status,
      'type': type,
      'text': text,
      'createdAt': createdAt?.toIso8601String(),
      'participant': participant,
      'name': name,
      'deleted': deleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'edited': edited,
      'editedAt': editedAt?.toIso8601String(),
      'originalText': originalText,
      'starred': starred,
      'edits': edits.map((e) => e.toJson()).toList(),
      'reactions': reactions,
      'quotedText': quotedText,
      'mimetype': mimetype,
      'filename': filename,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'locationAddress': locationAddress,
    };
  }
}
