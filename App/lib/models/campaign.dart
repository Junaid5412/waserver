class CampaignModel {
  final String id;
  final String name;
  final String status;
  final int total;
  final int sent;
  final int failed;
  final DateTime? scheduledAt;
  final DateTime? createdAt;

  CampaignModel({
    required this.id,
    required this.name,
    required this.status,
    this.total = 0,
    this.sent = 0,
    this.failed = 0,
    this.scheduledAt,
    this.createdAt,
  });

  factory CampaignModel.fromJson(Map<String, dynamic> json) {
    return CampaignModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Campaign',
      status: json['status']?.toString() ?? 'draft',
      total: (json['total'] is num) ? (json['total'] as num).toInt() : 0,
      sent: (json['sent'] is num) ? (json['sent'] as num).toInt() : 0,
      failed: (json['failed'] is num) ? (json['failed'] as num).toInt() : 0,
      scheduledAt: json['scheduledAt'] != null ? DateTime.tryParse(json['scheduledAt'].toString()) : null,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
    );
  }
}
