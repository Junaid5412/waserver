import '../models/user.dart';

class UserPermissions {
  final bool canViewDeletedMessages;
  final bool canViewEditedHistory;
  final bool canViewStatusSeen;
  final bool canViewMessageSeen;
  // WhatsApp feature-level permissions
  final bool canAccessChats;
  final bool canAccessGroups;
  final bool canAccessStatus;
  final bool canAccessCommunities;
  final bool canSendMedia;
  final bool canUseAi;
  final bool canDeleteMessages;

  const UserPermissions({
    this.canViewDeletedMessages = false,
    this.canViewEditedHistory = false,
    this.canViewStatusSeen = false,
    this.canViewMessageSeen = false,
    this.canAccessChats = true,
    this.canAccessGroups = true,
    this.canAccessStatus = true,
    this.canAccessCommunities = true,
    this.canSendMedia = true,
    this.canUseAi = true,
    this.canDeleteMessages = false,
  });

  factory UserPermissions.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserPermissions();
    return UserPermissions(
      canViewDeletedMessages: map['canViewDeletedMessages'] == true,
      canViewEditedHistory: map['canViewEditedHistory'] == true,
      canViewStatusSeen: map['canViewStatusSeen'] == true,
      canViewMessageSeen: map['canViewMessageSeen'] == true,
      canAccessChats: map['canAccessChats'] != false,
      canAccessGroups: map['canAccessGroups'] != false,
      canAccessStatus: map['canAccessStatus'] != false,
      canAccessCommunities: map['canAccessCommunities'] != false,
      canSendMedia: map['canSendMedia'] != false,
      canUseAi: map['canUseAi'] != false,
      canDeleteMessages: map['canDeleteMessages'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'canViewDeletedMessages': canViewDeletedMessages,
      'canViewEditedHistory': canViewEditedHistory,
      'canViewStatusSeen': canViewStatusSeen,
      'canViewMessageSeen': canViewMessageSeen,
      'canAccessChats': canAccessChats,
      'canAccessGroups': canAccessGroups,
      'canAccessStatus': canAccessStatus,
      'canAccessCommunities': canAccessCommunities,
      'canSendMedia': canSendMedia,
      'canUseAi': canUseAi,
      'canDeleteMessages': canDeleteMessages,
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

  static bool canAccessChatsSection(UserModel? user) {
    if (user == null) return true;
    if (user.isAdmin) return true;
    return user.permissions.canAccessChats;
  }

  static bool canAccessGroupsSection(UserModel? user) {
    if (user == null) return true;
    if (user.isAdmin) return true;
    return user.permissions.canAccessGroups;
  }

  static bool canAccessStatusSection(UserModel? user) {
    if (user == null) return true;
    if (user.isAdmin) return true;
    return user.permissions.canAccessStatus;
  }

  static bool canAccessCommunitiesSection(UserModel? user) {
    if (user == null) return true;
    if (user.isAdmin) return true;
    return user.permissions.canAccessCommunities;
  }

  static bool canSendMediaAttachments(UserModel? user) {
    if (user == null) return true;
    if (user.isAdmin) return true;
    return user.permissions.canSendMedia;
  }

  static bool canUseAiAssistant(UserModel? user) {
    if (user == null) return true;
    if (user.isAdmin) return true;
    return user.permissions.canUseAi;
  }

  static bool canDeleteMsg(UserModel? user) {
    if (user == null) return false;
    if (user.isAdmin) return true;
    return user.permissions.canDeleteMessages;
  }
}
