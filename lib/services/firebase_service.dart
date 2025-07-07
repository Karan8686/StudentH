import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/student.dart';
import '../models/teacher.dart';
import '../models/audit_log.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  // Authentication methods
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        print('Google Sign-In was cancelled by user');
        return null;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      print(
        'Successfully signed in with Google: \\${userCredential.user?.email}',
      );
      return userCredential;
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      print('Successfully signed out');
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  User? get currentUser => _auth.currentUser;

  // Firestore methods for student data
  Future<void> uploadStudentsToFirestore(List<Student> students) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final batch = _firestore.batch();

      for (Student student in students) {
        final docRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('students')
            .doc(student.id);
        batch.set(docRef, {
          'data': student.data,
          'name': student.name,
          'school': student.school,
          'division': student.division,
          'standard': student.standard,
          'studentNumber': student.studentNumber,
          'totalFees': student.totalFees,
          'paidFees': student.paidFees,
          'pendingFees': student.pendingFees,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print(
        'Successfully uploaded ${students.length} students to Firestore for user ${user.email}',
      );
    } catch (e) {
      print('Error uploading students to Firestore: $e');
      rethrow;
    }
  }

  Future<List<Student>> getStudentsFromFirestore() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final querySnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('students')
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return Student.fromMap(data['data'] as Map<String, dynamic>, doc.id);
      }).toList();
    } catch (e) {
      print('Error getting students from Firestore: $e');
      return [];
    }
  }

  Future<void> updateStudentInFirestore(Student student) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('students')
          .doc(student.id)
          .update({
            'data': student.data,
            'name': student.name,
            'school': student.school,
            'division': student.division,
            'standard': student.standard,
            'studentNumber': student.studentNumber,
            'totalFees': student.totalFees,
            'paidFees': student.paidFees,
            'pendingFees': student.pendingFees,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error updating student in Firestore: $e');
      rethrow;
    }
  }

  Future<void> deleteStudentFromFirestore(String studentId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('students')
          .doc(studentId)
          .delete();
    } catch (e) {
      print('Error deleting student from Firestore: $e');
      rethrow;
    }
  }

  // Firebase Storage methods for Excel files
  Future<String?> uploadExcelFileToStorage(
    Uint8List fileBytes,
    String fileName,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('User not authenticated');
        return null;
      }

      final storageRef = _storage.ref().child(
        'excel_files/${user.uid}/$fileName',
      );
      final uploadTask = storageRef.putData(fileBytes);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      print('Excel file uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('Error uploading Excel file to Storage: $e');
      return null;
    }
  }

  Future<List<String>> getExcelFilesFromStorage() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('User not authenticated');
        return [];
      }

      final storageRef = _storage.ref().child('excel_files/${user.uid}');
      final result = await storageRef.listAll();

      List<String> downloadUrls = [];
      for (var item in result.items) {
        final url = await item.getDownloadURL();
        downloadUrls.add(url);
      }

      return downloadUrls;
    } catch (e) {
      print('Error getting Excel files from Storage: $e');
      return [];
    }
  }

  // Sync methods
  Future<void> syncDataToCloud(
    List<Student> students,
    List<String> columns,
    String fileName, {
    String?
    existingFileId, // Optional: if provided, update existing file instead of creating new
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      print('Starting sync for user: ${user.email}');
      print('Students to sync: ${students.length}');
      print('Columns: $columns');

      String fileId;

      if (existingFileId != null) {
        // Update existing file
        fileId = existingFileId;
        print('Updating existing file: $fileId');

        // Clear existing students and add new ones
        await _clearStudentsFromFile(fileId);
        await uploadStudentsToFirestoreWithFileId(students, fileId);

        // Update metadata
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('metadata')
            .doc(fileId)
            .update({
              'columns': columns,
              'fileName': fileName,
              'studentCount': students.length,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
      } else {
        // Create new file
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        fileId = 'file_$timestamp';
        print('Creating new file: $fileId');

        // Upload students to Firestore with file ID
        await uploadStudentsToFirestoreWithFileId(students, fileId);

        // Save metadata with file ID
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('metadata')
            .doc(fileId)
            .set({
              'columns': columns,
              'fileName': fileName,
              'fileId': fileId,
              'timestamp': timestamp,
              'uploadDate': FieldValue.serverTimestamp(),
              'studentCount': students.length,
              'userEmail': user.email,
            });

        // Update the list of available files
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('metadata')
            .doc('file_list')
            .set({
              'files': FieldValue.arrayUnion([fileId]),
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

      print(
        'Data synced to cloud successfully for user ${user.email} with file ID: $fileId',
      );
    } catch (e) {
      print('Error syncing data to cloud: $e');
      rethrow;
    }
  }

  // Clear all students from a specific file
  Future<void> _clearStudentsFromFile(String fileId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final collection = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('files')
          .doc(fileId)
          .collection('students');

      final batch = _firestore.batch();
      final snapshot = await collection.get();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('Cleared all students from file: $fileId');
    } catch (e) {
      print('Error clearing students from file: $e');
      rethrow;
    }
  }

  Future<void> uploadStudentsToFirestoreWithFileId(
    List<Student> students,
    String fileId,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final batch = _firestore.batch();

      for (Student student in students) {
        final docRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('files')
            .doc(fileId)
            .collection('students')
            .doc(student.id);
        batch.set(docRef, {
          'data': student.data,
          'name': student.name,
          'school': student.school,
          'division': student.division,
          'standard': student.standard,
          'studentNumber': student.studentNumber,
          'totalFees': student.totalFees,
          'paidFees': student.paidFees,
          'pendingFees': student.pendingFees,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print(
        'Successfully uploaded ${students.length} students to Firestore for file ID: $fileId',
      );
    } catch (e) {
      print('Error uploading students to Firestore: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableFiles() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      print('DEBUG: Getting available files for user: ${user.email}');

      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('metadata')
          .doc('file_list')
          .get();

      print('DEBUG: file_list document exists: ${doc.exists}');
      print('DEBUG: file_list data: ${doc.data()}');

      if (!doc.exists || doc.data()?['files'] == null) {
        print('DEBUG: No file_list found or no files array');
        return [];
      }

      final List<String> fileIds = List<String>.from(doc.data()!['files']);
      print('DEBUG: File IDs found: $fileIds');

      List<Map<String, dynamic>> files = [];

      for (String fileId in fileIds) {
        print('DEBUG: Getting metadata for file: $fileId');
        final metadataDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('metadata')
            .doc(fileId)
            .get();

        if (metadataDoc.exists) {
          final data = metadataDoc.data()!;
          files.add({
            'fileId': fileId,
            'fileName': data['fileName'] ?? 'Unknown',
            'timestamp': data['timestamp'] ?? 0,
            'uploadDate': data['uploadDate'],
            'studentCount': data['studentCount'] ?? 0,
          });
          print('DEBUG: Added file: $fileId with name: ${data['fileName']}');
        } else {
          print('DEBUG: Metadata not found for file: $fileId');
        }
      }

      // Sort by timestamp (newest first)
      files.sort(
        (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
      );
      print(
        'DEBUG: Final files list: ${files.map((f) => f['fileId']).toList()}',
      );
      return files;
    } catch (e) {
      print('DEBUG: Error getting available files: $e');
      return [];
    }
  }

  Future<List<Student>> getStudentsFromFile(String fileId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final querySnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('files')
          .doc(fileId)
          .collection('students')
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return Student.fromMap(data['data'] as Map<String, dynamic>, doc.id);
      }).toList();
    } catch (e) {
      print('Error getting students from file: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getFileMetadata(String fileId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('metadata')
          .doc(fileId)
          .get();

      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('Error getting file metadata: $e');
      return null;
    }
  }

  Future<void> deleteAllStudentsFromFirestore() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      final collection = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('students');
      final batch = _firestore.batch();
      final snapshot = await collection.get();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print(
        'All students deleted from Firestore for user [38;5;2m${user.email}[0m',
      );
    } catch (e) {
      print('Error deleting all students from Firestore: $e');
      rethrow;
    }
  }

  // CRUD operations for specific files
  Future<void> addStudentToFile(Student student, String fileId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('files')
          .doc(fileId)
          .collection('students')
          .doc(student.id)
          .set({
            'data': student.data,
            'name': student.name,
            'school': student.school,
            'division': student.division,
            'standard': student.standard,
            'studentNumber': student.studentNumber,
            'totalFees': student.totalFees,
            'paidFees': student.paidFees,
            'pendingFees': student.pendingFees,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error adding student to file: $e');
      rethrow;
    }
  }

  Future<void> updateStudentInFile(Student student, String fileId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('files')
          .doc(fileId)
          .collection('students')
          .doc(student.id)
          .update({
            'data': student.data,
            'name': student.name,
            'school': student.school,
            'division': student.division,
            'standard': student.standard,
            'studentNumber': student.studentNumber,
            'totalFees': student.totalFees,
            'paidFees': student.paidFees,
            'pendingFees': student.pendingFees,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error updating student in file: $e');
      rethrow;
    }
  }

  Future<void> deleteStudentFromFile(String studentId, String fileId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('files')
          .doc(fileId)
          .collection('students')
          .doc(studentId)
          .delete();
    } catch (e) {
      print('Error deleting student from file: $e');
      rethrow;
    }
  }

  // Firestore methods for teacher data
  Future<void> uploadTeachersToFirestore(List<Teacher> teachers) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final batch = _firestore.batch();

      for (Teacher teacher in teachers) {
        final docRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('teachers')
            .doc(teacher.id);
        batch.set(docRef, teacher.toMap());
      }

      await batch.commit();
      print(
        'Successfully uploaded \\${teachers.length} teachers to Firestore for user \\${user.email}',
      );
    } catch (e) {
      print('Error uploading teachers to Firestore: $e');
      rethrow;
    }
  }

  Future<List<Teacher>> getTeachersFromFirestore() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final querySnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('teachers')
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return Teacher.fromMap(data, doc.id);
      }).toList();
    } catch (e) {
      print('Error getting teachers from Firestore: $e');
      return [];
    }
  }

  Future<void> updateTeacherInFirestore(Teacher teacher) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('teachers')
          .doc(teacher.id)
          .update(teacher.toMap());
    } catch (e) {
      print('Error updating teacher in Firestore: $e');
      rethrow;
    }
  }

  Future<void> deleteTeacherFromFirestore(String teacherId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('teachers')
          .doc(teacherId)
          .delete();
    } catch (e) {
      print('Error deleting teacher from Firestore: $e');
      rethrow;
    }
  }

  // Firestore methods for lectures under each teacher
  Future<void> addLecture(String teacherId, Lecture lecture) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('teachers')
          .doc(teacherId)
          .collection('lectures')
          .doc(lecture.id)
          .set(lecture.toMap());
    } catch (e) {
      print('Error adding lecture: $e');
      rethrow;
    }
  }

  Future<List<Lecture>> getLectures(String teacherId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');
      final querySnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('teachers')
          .doc(teacherId)
          .collection('lectures')
          .get();
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return Lecture.fromMap(data, doc.id, teacherId);
      }).toList();
    } catch (e) {
      print('Error getting lectures: $e');
      return [];
    }
  }

  Future<void> updateLecture(String teacherId, Lecture lecture) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('teachers')
          .doc(teacherId)
          .collection('lectures')
          .doc(lecture.id)
          .update(lecture.toMap());
    } catch (e) {
      print('Error updating lecture: $e');
      rethrow;
    }
  }

  Future<void> deleteLecture(String teacherId, String lectureId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('teachers')
          .doc(teacherId)
          .collection('lectures')
          .doc(lectureId)
          .delete();
    } catch (e) {
      print('Error deleting lecture: $e');
      rethrow;
    }
  }

  Future<Student?> getStudentFromFirestore(String studentId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('students')
          .doc(studentId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null || data['data'] == null) return null;
      return Student.fromMap(Map<String, dynamic>.from(data['data']), doc.id);
    } catch (e) {
      print('Error getting student from Firestore: $e');
      return null;
    }
  }

  // Public wrapper for clearing students from a file
  Future<void> clearStudentsFromFile(String fileId) async {
    return _clearStudentsFromFile(fileId);
  }

  // Public method to update file metadata
  Future<void> updateFileMetadata(
    String userId,
    String fileId,
    List<String> columns,
    String fileName,
    int studentCount,
  ) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('metadata')
        .doc(fileId)
        .set({
          'columns': columns,
          'fileName': fileName,
          'studentCount': studentCount,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  // Sync local audit logs to Firestore, keeping only the 10 most recent in Firestore
  Future<void> syncAuditLogs(
    List<AuditLog> localLogs,
    String userId,
    String fileId,
  ) async {
    final auditCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('files')
        .doc(fileId)
        .collection('audit_logs');

    // 1. Get only local logs with priority 0 (not yet synced)
    final newLogs = localLogs.where((log) => log.priority == 0).toList();
    if (newLogs.isEmpty) return;

    // 2. Upload new logs
    final batch = _firestore.batch();
    for (final log in newLogs) {
      final docRef = auditCollection.doc(log.id);
      batch.set(docRef, log.toJson());
    }
    await batch.commit();

    // 3. Fetch all logs in Firestore, order by timestamp/ID (assuming ID is sortable by time)
    final snapshot = await auditCollection
        .orderBy('timestamp', descending: true)
        .get();
    final docs = snapshot.docs;
    if (docs.length > 10) {
      // 4. Delete older logs, keep only 10 most recent
      final toDelete = docs.skip(10);
      final delBatch = _firestore.batch();
      for (final doc in toDelete) {
        delBatch.delete(doc.reference);
      }
      await delBatch.commit();
    }

    // 5. Mark synced logs as priority 1 locally (should be done in ViewModel after successful sync)
  }
}
