import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/student.dart';
import '../services/firebase_service.dart';
import '../services/audit_service.dart';

class StudentViewModel extends ChangeNotifier {
  List<String> _columns = [];
  List<Student> _students = [];
  List<Student> _filteredStudents = [];
  String? _fileName;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  String? _currentFileId; // Track current active file
  bool onlyPendingFeesFilter = false;
  double? pendingFeesMinFilter;

  // Firebase service
  final FirebaseService _firebaseService = FirebaseService();
  final AuditService _auditService = AuditService();

  // Getters
  List<String> get columns => _columns;
  List<Student> get students => _students;
  List<Student> get filteredStudents => _filteredStudents;
  String? get fileName => _fileName;
  String get searchQuery => _searchQuery;
  String get selectedFilter => _selectedFilter;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _firebaseService.currentUser != null;
  bool get hasData =>
      _students.isNotEmpty && _columns.isNotEmpty && _fileName != null;
  bool get isPendingFilterActive =>
      onlyPendingFeesFilter ||
      (pendingFeesMinFilter != null && pendingFeesMinFilter! > 0);

  Set<String> get divisionOptions {
    return _students
        .map((student) => student.division)
        .where((div) => div.isNotEmpty)
        .toSet();
  }

  Set<String> get schoolOptions {
    return _students
        .map((student) => student.school)
        .where((school) => school.isNotEmpty)
        .toSet();
  }

  Set<String> get standardOptions {
    return _students
        .map((student) => student.standard)
        .where((standard) => standard.isNotEmpty)
        .toSet();
  }

  // Initialize and load saved data
  Future<void> initialize() async {
    if (_isInitialized) return;

    _setLoading(true);
    try {
      await initializeData();
    } catch (e) {
      print('DEBUG: Error loading saved data: $e');
    } finally {
      _setLoading(false);
      _isInitialized = true;
      notifyListeners();
    }
  }

  // Initialize data
  Future<void> initializeData() async {
    // Always load local data first
    await loadDataFromLocal();

    // Then try to load from cloud if authenticated
    if (isAuthenticated) {
      await loadDataFromCloud();
    }
  }

  // Load data from local storage
  Future<void> loadDataFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentsJson = prefs.getString('students');
      final columnsJson = prefs.getString('columns');
      final currentFileId = prefs.getString('currentFileId');
      final fileName = prefs.getString('fileName');

      if (studentsJson != null) {
        final List<dynamic> studentsList = json.decode(studentsJson);
        _students = studentsList.map((json) => Student.fromJson(json)).toList();
      }

      if (columnsJson != null) {
        _columns = List<String>.from(json.decode(columnsJson));
      }

      if (currentFileId != null) {
        _currentFileId = currentFileId;
      }

      if (fileName != null) {
        _fileName = fileName;
      }

      _applyFilters();
      notifyListeners();
    } catch (e) {
      _error = 'Error loading local data: $e';
      notifyListeners();
    }
  }

  // Load data from cloud
  Future<void> loadDataFromCloud() async {
    if (!isAuthenticated) return;

    try {
      _isLoading = true;
      notifyListeners();

      // Get the most recent file (first in the sorted list)
      final availableFiles = await _firebaseService.getAvailableFiles();

      if (availableFiles.isNotEmpty) {
        final latestFile = availableFiles.first;

        final cloudStudents = await _firebaseService.getStudentsFromFile(
          latestFile['fileId'],
        );

        final metadata = await _firebaseService.getFileMetadata(
          latestFile['fileId'],
        );

        if (cloudStudents.isNotEmpty) {
          // Only update if cloud data is available
          _students = cloudStudents;
          _currentFileId = latestFile['fileId']; // Set current file ID
          if (metadata != null && metadata['columns'] != null) {
            _columns = List<String>.from(metadata['columns']);
          }
          if (metadata != null && metadata['fileName'] != null) {
            _fileName = metadata['fileName'];
          }
          await _saveDataToLocal();
        } else {
          // Keep existing local data if cloud file is empty
        }
      } else {
        // Keep existing local data if no cloud files
      }

      _applyFilters();
      _error = null;
    } catch (e) {
      _error = 'Error loading cloud data: $e';
      // Keep existing local data on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load data from specific file
  Future<void> loadDataFromFile(String fileId) async {
    if (!isAuthenticated) return;

    try {
      _isLoading = true;
      notifyListeners();

      final cloudStudents = await _firebaseService.getStudentsFromFile(fileId);
      final metadata = await _firebaseService.getFileMetadata(fileId);

      if (cloudStudents.isNotEmpty) {
        _students = cloudStudents;
        _currentFileId = fileId; // Set current file ID
        if (metadata != null && metadata['columns'] != null) {
          _columns = List<String>.from(metadata['columns']);
        }
        if (metadata != null && metadata['fileName'] != null) {
          _fileName = metadata['fileName'];
        }
        await _saveDataToLocal();
      }

      _applyFilters();
      _error = null;
    } catch (e) {
      _error = 'Error loading file data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Save data to local storage
  Future<void> _saveDataToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentsJson = json.encode(
        _students.map((s) => s.toJson()).toList(),
      );
      final columnsJson = json.encode(_columns);

      await prefs.setString('students', studentsJson);
      await prefs.setString('columns', columnsJson);
      await prefs.setString('currentFileId', _currentFileId ?? '');
      await prefs.setString('fileName', _fileName ?? '');
    } catch (e) {
      _error = 'Error saving local data: $e';
      notifyListeners();
    }
  }

  // Sync data to cloud
  Future<void> syncToCloud(String fileName) async {
    if (!isAuthenticated) {
      _error = 'Please sign in to sync to cloud';
      notifyListeners();
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      // If we have a current file, update it. Otherwise create new file
      await _firebaseService.syncDataToCloud(
        _students,
        _columns,
        fileName,
        existingFileId:
            _currentFileId, // Pass current file ID to update instead of create new
      );

      // If this was a new file, get the file ID
      if (_currentFileId == null) {
        final availableFiles = await _firebaseService.getAvailableFiles();
        if (availableFiles.isNotEmpty) {
          _currentFileId = availableFiles.first['fileId'];
        }
      }

      _error = null;
    } catch (e) {
      _error = 'Error syncing to cloud: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Upload Excel file to cloud
  Future<String?> uploadExcelToCloud(
    Uint8List fileBytes,
    String fileName,
  ) async {
    if (!isAuthenticated) {
      _error = 'Please sign in to upload files';
      notifyListeners();
      return null;
    }

    try {
      return await _firebaseService.uploadExcelFileToStorage(
        fileBytes,
        fileName,
      );
    } catch (e) {
      _error = 'Error uploading file to cloud: $e';
      notifyListeners();
      return null;
    }
  }

  // Add this top-level function for compute
  Map<String, dynamic> _parseExcelInBackground(Map<String, dynamic> args) {
    final Uint8List fileBytes = args['fileBytes'];
    final String fileName = args['fileName'];
    final excel = Excel.decodeBytes(fileBytes);
    final sheetNames = excel.tables.keys.toList();
    if (sheetNames.isEmpty) {
      throw Exception('Excel file contains no sheets');
    }
    final sheet = excel.tables[sheetNames.first];
    if (sheet == null) {
      throw Exception('Could not access the first sheet');
    }
    // Extract headers from first row
    final List<String> columns = [];
    final headerRow = sheet.row(0);
    for (int col = 0; col < sheet.maxColumns; col++) {
      String columnName = '';
      if (col < headerRow.length) {
        final cellValue = headerRow[col];
        if (cellValue != null && cellValue.value != null) {
          columnName = cellValue.value.toString().trim();
        }
      }
      if (columnName.isEmpty) {
        columnName = 'Column_${col + 1}';
      }
      columns.add(columnName);
    }
    // Parse data rows
    final List<Map<String, dynamic>> students = [];
    final totalRows = sheet.maxRows;
    for (int row = 1; row < totalRows; row++) {
      final rowData = <String, dynamic>{};
      bool hasData = false;
      final currentRow = sheet.row(row);
      for (int col = 0; col < columns.length; col++) {
        String value = '';
        if (col < currentRow.length) {
          final cellValue = currentRow[col];
          if (cellValue != null && cellValue.value != null) {
            value = cellValue.value.toString().trim();
            if (value.isNotEmpty) hasData = true;
          }
        }
        rowData[columns[col]] = value;
      }
      if (hasData) {
        final studentId = 'row_${row}_${DateTime.now().millisecondsSinceEpoch}';
        rowData['id'] = studentId;
        students.add(rowData);
      }
    }
    return {'columns': columns, 'students': students, 'fileName': fileName};
  }

  // Parse Excel file
  Future<void> parseExcelFile(Uint8List fileBytes, String fileName) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      // Offload parsing to background isolate
      final result = await compute(_parseExcelInBackground, {
        'fileBytes': fileBytes,
        'fileName': fileName,
      });
      _columns = List<String>.from(result['columns']);
      _students = (result['students'] as List)
          .map((rowData) => Student.fromMap(rowData, rowData['id'] as String))
          .toList();
      _fileName = fileName;
      await _saveDataToLocal();
      // Upload Excel file to cloud storage if authenticated
      if (isAuthenticated) {
        try {
          final downloadUrl = await uploadExcelToCloud(fileBytes, fileName);
          print('Excel file uploaded to cloud storage: $downloadUrl');
        } catch (e) {
          print('Error uploading Excel file to cloud storage: $e');
        }
      }
      // Sync data to Firestore if authenticated using new file versioning system
      if (isAuthenticated) {
        try {
          await syncToCloud(fileName);
          print('Data synced to cloud with file versioning');
        } catch (e) {
          print('Error syncing data to cloud: $e');
        }
      }
      _applyFilters();
      print('DEBUG: Excel parsing completed successfully');
    } catch (e, stackTrace) {
      print('DEBUG: Error in parseExcelFile: $e');
      print('DEBUG: Stack trace: $stackTrace');
      _error = 'Error parsing Excel file: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Search and filter methods
  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void setFilter(String filter) {
    _selectedFilter = filter;
    _applyFilters();
    notifyListeners();
  }

  void setPendingFeesFilter(bool onlyPending, double? minPending) {
    onlyPendingFeesFilter = onlyPending;
    pendingFeesMinFilter = minPending;
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    // Always start from the full student list
    List<Student> filtered = List.from(_students);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((student) {
        return student.name.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ) ||
            student.school.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            student.studentNumber.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            );
      }).toList();
    }

    // Apply division/standard filter
    if (_selectedFilter != 'All') {
      filtered = filtered
          .where(
            (student) =>
                student.division == _selectedFilter ||
                student.standard == _selectedFilter,
          )
          .toList();
    }

    // Apply pending fees filters
    if (onlyPendingFeesFilter) {
      filtered = filtered.where((s) => s.pendingFeesAmount > 0).toList();
    }
    if (pendingFeesMinFilter != null && pendingFeesMinFilter! > 0) {
      filtered = filtered
          .where((s) => s.pendingFeesAmount >= pendingFeesMinFilter!)
          .toList();
    }

    _filteredStudents = filtered;
    notifyListeners();
  }

  // Get unique filters
  List<String> get availableFilters {
    final filters = <String>{'All'};
    for (final student in _students) {
      filters.add(student.division);
      filters.add(student.standard);
    }
    return filters.toList()..sort();
  }

  // Student CRUD operations
  Future<void> addStudent(Student student, {bool skipLogging = false}) async {
    try {
      _students.add(student);
      await _saveDataToLocal();

      // Add audit log (skip for undo operations)
      if (!skipLogging) {
        await _auditService.addLog(
          action: 'add',
          studentId: student.id,
          studentName: student.name,
          newData: student.data,
        );
      }

      // Update in cloud if authenticated
      if (isAuthenticated) {
        if (_currentFileId != null) {
          // Use new file-based system
          await _firebaseService.addStudentToFile(student, _currentFileId!);
        } else {
          // Fallback to old system for backward compatibility
          await _firebaseService.uploadStudentsToFirestore([student]);
        }
      }

      _applyFilters();
      notifyListeners();
    } catch (e) {
      _error = 'Error adding student: $e';
      notifyListeners();
    }
  }

  Future<void> updateStudent(
    Student student, {
    bool skipLogging = false,
  }) async {
    try {
      final index = _students.indexWhere((s) => s.id == student.id);
      if (index != -1) {
        final oldStudent = _students[index];
        _students[index] = student;
        await _saveDataToLocal();

        // Add audit log (skip for undo operations)
        if (!skipLogging) {
          await _auditService.addLog(
            action: 'update',
            studentId: student.id,
            studentName: student.name,
            oldData: oldStudent.data,
            newData: student.data,
          );
        }

        // Update in cloud if authenticated
        if (isAuthenticated) {
          if (_currentFileId != null) {
            // Use new file-based system
            await _firebaseService.updateStudentInFile(
              student,
              _currentFileId!,
            );
          } else {
            // Fallback to old system for backward compatibility
            await _firebaseService.updateStudentInFirestore(student);
            // Fetch latest student data from Firestore and update local list
            final latest = await _firebaseService.getStudentFromFirestore(
              student.id,
            );
            if (latest != null) {
              _students[index] = latest;
            }
          }
        }

        _applyFilters();
        notifyListeners();
      }
    } catch (e) {
      _error = 'Error updating student: $e';
      notifyListeners();
    }
  }

  Future<void> deleteStudent(
    String studentId, {
    bool skipLogging = false,
  }) async {
    try {
      final studentToDelete = _students.firstWhere((s) => s.id == studentId);
      _students.removeWhere((s) => s.id == studentId);
      await _saveDataToLocal();

      // Add audit log (skip for undo operations)
      if (!skipLogging) {
        await _auditService.addLog(
          action: 'delete',
          studentId: studentId,
          studentName: studentToDelete.name,
          oldData: studentToDelete.data,
        );
      }

      // Delete from cloud if authenticated
      if (isAuthenticated) {
        if (_currentFileId != null) {
          // Use new file-based system
          await _firebaseService.deleteStudentFromFile(
            studentId,
            _currentFileId!,
          );
        } else {
          // Fallback to old system for backward compatibility
          await _firebaseService.deleteStudentFromFirestore(studentId);
        }
      }

      _applyFilters();
      notifyListeners();
    } catch (e) {
      _error = 'Error deleting student: $e';
      notifyListeners();
    }
  }

  Student? getStudentById(String id) {
    try {
      return _students.firstWhere((student) => student.id == id);
    } catch (e) {
      return null;
    }
  }

  // Utility methods
  void clearFilters() {
    _searchQuery = '';
    _selectedFilter = 'All';
    _applyFilters();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('students');
      await prefs.remove('columns');
      await prefs.remove('currentFileId');
      await prefs.remove('fileName');

      _columns = [];
      _students = [];
      _fileName = null;
      _currentFileId = null;
      clearFilters();
      notifyListeners();
    } catch (e) {
      _error = 'Error clearing data: $e';
      notifyListeners();
    }
  }

  Future<void> loadExcelFile() async {
    _setLoading(true);
    clearError();

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null) {
        _setLoading(false);
        return;
      }

      Uint8List? fileBytes = result.files.single.bytes;

      if (fileBytes == null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        if (await file.exists()) {
          fileBytes = await file.readAsBytes();
        }
      }

      if (fileBytes == null) {
        _setError('Could not read file');
        _setLoading(false);
        return;
      }

      await parseExcelFile(fileBytes, result.files.single.name);
    } catch (e) {
      _setError('Error parsing file: $e');
      _setLoading(false);
    }
  }

  Future<String> exportData() async {
    try {
      final data = {
        'columns': _columns,
        'students': _students.map((s) => s.toJson()).toList(),
        'exportedAt': DateTime.now().toIso8601String(),
      };
      return json.encode(data);
    } catch (e) {
      _error = 'Error exporting data: $e';
      notifyListeners();
      return '';
    }
  }

  // Export current student data to Excel
  Future<Uint8List> exportToExcel() async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    // Write header
    sheet.appendRow(_columns.map((col) => TextCellValue(col)).toList());
    // Write data
    for (final student in _students) {
      final row = _columns
          .map((col) => TextCellValue(student.data[col]?.toString() ?? ''))
          .toList();
      sheet.appendRow(row);
    }
    final encoded = excel.encode();
    if (encoded == null) {
      throw Exception('Failed to encode Excel file');
    }
    return Uint8List.fromList(encoded);
  }

  // Private helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  Future<void> clearAllDataFromFirestore() async {
    try {
      await _firebaseService.deleteAllStudentsFromFirestore();
    } catch (e) {
      _error = 'Error clearing data from Firestore: $e';
      notifyListeners();
      rethrow;
    }
  }

  // Get available files from cloud
  Future<List<Map<String, dynamic>>> getAvailableFiles() async {
    if (!isAuthenticated) return [];

    try {
      final files = await _firebaseService.getAvailableFiles();
      return files;
    } catch (e) {
      _error = 'Error getting available files: $e';
      notifyListeners();
      return [];
    }
  }
}
