import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/audit_log.dart';
import '../models/student.dart';

class AuditService {
  static final AuditService _instance = AuditService._internal();
  factory AuditService() => _instance;
  AuditService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const int maxLogs = 10;

  // Add audit log
  Future<void> addLog({
    required String action,
    required String studentId,
    required String studentName,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    bool skipLogging = false,
  }) async {
    if (skipLogging) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final auditLog = AuditLog(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      action: action,
      studentId: studentId,
      studentName: studentName,
      oldData: oldData,
      newData: newData,
      timestamp: DateTime.now(),
      userEmail: user.email ?? '',
    );

    // Save to local storage
    await _saveToLocal(auditLog);

    // Save to cloud if authenticated
    if (user != null) {
      await _saveToCloud(auditLog);
    }
  }

  // Save to local storage
  Future<void> _saveToLocal(AuditLog auditLog) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getString('audit_logs') ?? '[]';
      final List<dynamic> logsList = json.decode(logsJson);

      // Add new log at the beginning
      logsList.insert(0, auditLog.toMap());

      // Keep only the latest 10 logs
      if (logsList.length > maxLogs) {
        logsList.removeRange(maxLogs, logsList.length);
      }

      await prefs.setString('audit_logs', json.encode(logsList));
    } catch (e) {
      print('Error saving audit log to local: $e');
    }
  }

  // Save to cloud
  Future<void> _saveToCloud(AuditLog auditLog) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('audit_logs')
          .doc(auditLog.id)
          .set({
            ...auditLog.toMap(),
            'timestamp': FieldValue.serverTimestamp(),
          });

      // Keep only latest 10 logs in cloud
      await _cleanupCloudLogs(user.uid);
    } catch (e) {
      print('Error saving audit log to cloud: $e');
    }
  }

  // Cleanup old logs in cloud (keep only latest 10)
  Future<void> _cleanupCloudLogs(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('audit_logs')
          .orderBy('timestamp', descending: true)
          .get();

      if (querySnapshot.docs.length > maxLogs) {
        final batch = _firestore.batch();
        final docsToDelete = querySnapshot.docs.skip(maxLogs);

        for (final doc in docsToDelete) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      }
    } catch (e) {
      print('Error cleaning up cloud logs: $e');
    }
  }

  // Get audit logs
  Future<List<AuditLog>> getLogs() async {
    try {
      // Try to get from cloud first
      final user = _auth.currentUser;
      if (user != null) {
        final cloudLogs = await _getFromCloud(user.uid);
        if (cloudLogs.isNotEmpty) {
          await _saveToLocalFromCloud(cloudLogs);
          return cloudLogs;
        }
      }

      // Fallback to local storage
      return await _getFromLocal();
    } catch (e) {
      print('Error getting audit logs: $e');
      return await _getFromLocal();
    }
  }

  // Get from cloud
  Future<List<AuditLog>> _getFromCloud(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('audit_logs')
          .orderBy('timestamp', descending: true)
          .limit(maxLogs)
          .get();

      return querySnapshot.docs.map((doc) {
        return AuditLog.fromMap(doc.data(), doc.id);
      }).toList();
    } catch (e) {
      print('Error getting audit logs from cloud: $e');
      return [];
    }
  }

  // Get from local storage
  Future<List<AuditLog>> _getFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getString('audit_logs') ?? '[]';
      final List<dynamic> logsList = json.decode(logsJson);

      return logsList.map((log) {
        return AuditLog.fromMap(log, log['id'] ?? '');
      }).toList();
    } catch (e) {
      print('Error getting audit logs from local: $e');
      return [];
    }
  }

  // Save cloud logs to local
  Future<void> _saveToLocalFromCloud(List<AuditLog> logs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsList = logs.map((log) => log.toMap()).toList();
      await prefs.setString('audit_logs', json.encode(logsList));
    } catch (e) {
      print('Error saving cloud logs to local: $e');
    }
  }

  // Clear all logs
  Future<void> clearLogs() async {
    try {
      // Clear local
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('audit_logs');

      // Clear cloud
      final user = _auth.currentUser;
      if (user != null) {
        final querySnapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('audit_logs')
            .get();

        final batch = _firestore.batch();
        for (final doc in querySnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      print('Error clearing audit logs: $e');
    }
  }
}
