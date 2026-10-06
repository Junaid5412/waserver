import '../config/permissions.dart';

class UserModel {
  final String id;
  final String email;
  final String name;
  final String role;
  final bool disabled;
  final int instancesCount;
  final UserPermissions permissions;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.disabled = false,
    this.instancesCount = 0,
    this.permissions = const UserPermissions(),
  });

  bool get isAdmin => role == 'admin' || role == 'super_admin';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    int instances = 0;
    if (json['instances'] != null) {
      if (json['instances'] is int) {
        instances = json['instances'];
      } else if (json['instances'] is List) {
        instances = (json['instances'] as List).length;
      }
    } else if (json['instancesCount'] != null) {
      instances = int.tryParse(json['instancesCount'].toString()) ?? 0;
    }

    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      disabled: json['disabled'] == true,
      instancesCount: instances,
      permissions: UserPermissions.fromMap(
        json['permissions'] is Map ? Map<String, dynamic>.from(json['permissions']) : null,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'disabled': disabled,
      'instancesCount': instancesCount,
      'permissions': permissions.toMap(),
    };
  }
}
