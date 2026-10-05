import '../models/user.dart';

class UserPermissions {
  final bool canViewDeletedMessages;
  final bool canViewEditedHistory;
  final bool canViewStatusSeen;
  final bool canViewMessageSeen;

  const UserPermissions({
    this.canViewDeletedMessages = false,
    this.canViewEditedHistory = false,
    this.canViewStatusSeen = false,
    this.canViewMessageSeen = false,
  });

  factory UserPermissions.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserPermissions();
    return UserPermissions(
      canViewDeletedMessages: map['canViewDeletedMessages'] == true,
      canViewEditedHistory: map['canViewEditedHistory'] == true,
      canViewStatusSeen: map['canViewStatusSeen'] == true,
      canViewMessageSeen: map['canViewMessageSeen'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'canViewDeletedMessages': canViewDeletedMessages,
      'canViewEditedHistory': canViewEditedHistory,
      'canViewStatusSeen': canViewStatusSeen,
      'canViewMessageSeen': canViewMessageSeen,
    };
  }

  static bool canViewDeleted(UserModel? user) {
    if (user == null) return false;
    if (user.isAdmin) return true;
    return user.permissions.canViewDeletedMessages;
  }

  static bool canViewEdits(UserModel? user) {
    if (user == null) return false;
    if (user.isAdmin) return true;
    return user.permissions.canViewEditedHistory;
  }

  static bool canViewStatus(UserModel? user) {
    if (user == null) return false;
    if (user.isAdmin) return true;
    return user.permissions.canViewStatusSeen;
  }

  static bool canViewReceipts(UserModel? user) {
    if (user == null) return false;
    if (user.isAdmin) return true;
    return user.permissions.canViewMessageSeen;
  }
}
