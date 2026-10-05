class InstanceModel {
  final String id;
  final String name;
  final String status;
  final String? phone;
  final String? webhookUrl;
  final bool archived;

  InstanceModel({
    required this.id,
    required this.name,
    required this.status,
    this.phone,
    this.webhookUrl,
    this.archived = false,
  });

  bool get isConnected => status == 'connected';

  factory InstanceModel.fromJson(Map<String, dynamic> json) {
    return InstanceModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Instance',
      status: json['status']?.toString() ?? 'disconnected',
      phone: json['phone']?.toString(),
      webhookUrl: json['webhookUrl']?.toString(),
      archived: json['archived'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'phone': phone,
      'webhookUrl': webhookUrl,
      'archived': archived,
    };
  }
}
