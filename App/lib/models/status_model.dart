class StatusModel {
  final String id;
  final String waId;
  final String name;
  final String participantPhone;
  final String participantJid;
  final String text;
  final String type;
  final DateTime? createdAt;
  final bool fromMe;
  final List<String> viewers;
  final String? mimetype;
  final String? filename;
  final bool hasMedia;

  StatusModel({
    required this.id,
    this.waId = '',
    required this.name,
    this.participantPhone = '',
    this.participantJid = '',
    this.text = '',
    this.type = 'text',
    this.createdAt,
    this.fromMe = false,
    this.viewers = const [],
    this.mimetype,
    this.filename,
    this.hasMedia = false,
  });

  factory StatusModel.fromJson(Map<String, dynamic> json) {
    List<String> views = [];
    if (json['viewers'] is List) {
      views = (json['viewers'] as List).map((e) => e.toString()).toList();
    }
    final rawType = json['type']?.toString().toLowerCase() ?? 'text';
    final mime = json['mimetype']?.toString();
    final hasMedia = json['hasMedia'] == true ||
        rawType == 'image' ||
        rawType == 'video' ||
        (mime != null && (mime.startsWith('image/') || mime.startsWith('video/')));

    return StatusModel(
      id: json['id']?.toString() ?? '',
      waId: json['waId']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Status',
      participantPhone: json['participantPhone']?.toString() ?? '',
      participantJid: json['participantJid']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      type: rawType,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      fromMe: json['fromMe'] == true,
      viewers: views,
      mimetype: mime,
      filename: json['filename']?.toString(),
      hasMedia: hasMedia,
    );
  }
}
