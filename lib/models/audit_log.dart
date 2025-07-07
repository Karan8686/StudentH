import 'package:cloud_firestore/cloud_firestore.dart';

enum AuditAction { add, update, delete }

class AuditLog {
  final String id;
  final String action; // 'add', 'update', 'delete'
  final String studentId;
  final String studentName;
  final Map<String, dynamic>? oldData; // For undo
  final Map<String, dynamic>? newData; // For undo
  final DateTime timestamp;
  final String userEmail;

  AuditLog({
    required this.id,
    required this.action,
    required this.studentId,
    required this.studentName,
    this.oldData,
    this.newData,
    required this.timestamp,
    required this.userEmail,
  });

  Map<String, dynamic> toMap() {
    return {
      'action': action,
      'studentId': studentId,
      'studentName': studentName,
      'oldData': oldData,
      'newData': newData,
      'timestamp': timestamp,
      'userEmail': userEmail,
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> data, String id) {
    return AuditLog(
      id: id,
      action: data['action'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      oldData: data['oldData'],
      newData: data['newData'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      userEmail: data['userEmail'] ?? '',
    );
  }

  String get actionDisplay {
    switch (action) {
      case 'add':
        return 'Added';
      case 'update':
        return 'Updated';
      case 'delete':
        return 'Deleted';
      default:
        return 'Modified';
    }
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }
}
