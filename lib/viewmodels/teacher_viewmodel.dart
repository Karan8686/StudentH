import 'package:flutter/foundation.dart';
import '../models/teacher.dart';
import '../services/firebase_service.dart';

class TeacherViewModel extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  List<Teacher> _teachers = [];
  bool _isLoading = false;
  String? _error;

  List<Teacher> get teachers => _teachers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadTeachers() async {
    if (_teachers.isNotEmpty) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      _teachers = await _firebaseService.getTeachersFromFirestore();
      _error = null;
    } catch (e) {
      _error = 'Error loading teachers: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addTeacher(Teacher teacher) async {
    try {
      await _firebaseService.uploadTeachersToFirestore([teacher]);
      _teachers.add(teacher);
      notifyListeners();
    } catch (e) {
      _error = 'Error adding teacher: $e';
      notifyListeners();
    }
  }

  Future<void> updateTeacher(Teacher teacher) async {
    try {
      await _firebaseService.updateTeacherInFirestore(teacher);
      final idx = _teachers.indexWhere((t) => t.id == teacher.id);
      if (idx != -1) {
        _teachers[idx] = teacher;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Error updating teacher: $e';
      notifyListeners();
    }
  }

  Future<void> deleteTeacher(String teacherId) async {
    try {
      await _firebaseService.deleteTeacherFromFirestore(teacherId);
      _teachers.removeWhere((t) => t.id == teacherId);
      notifyListeners();
    } catch (e) {
      _error = 'Error deleting teacher: $e';
      notifyListeners();
    }
  }
}
