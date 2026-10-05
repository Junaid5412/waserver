class StatusModel {
  final String id;
  final String name;
  final String participantPhone;
  final String participantJid;
  final String text;
  final String type;
  final DateTime? createdAt;
  final bool fromMe;
  final List<String> viewers;

  StatusModel({
    required this.id,
    required this.name,
    this.participantPhone = '',
    this.participantJid = '',
    this.text = '',
    this.type = 'text',
    this.createdAt,
    this.fromMe = false,
    this.viewers = const [],
  });

  factory StatusModel.fromJson(Map<String, dynamic> json) {
    List<String> views = [];
    if (json['viewers'] is List) {
      views = (json['viewers'] as List).map((e) => e.toString()).toList();
    }
    return StatusModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Status',
      participantPhone: json['participantPhone']?.toString() ?? '',
      participantJid: json['participantJid']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      fromMe: json['fromMe'] == true,
      viewers: views,
    );
  }
}
