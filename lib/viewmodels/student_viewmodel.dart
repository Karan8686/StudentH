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
import '../models/audit_log.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';

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
  double _progress = 0.0;
  double _uploadProgress = 0.0;
  bool _isUploadingToCloud = false;
  List<AuditLog> _auditLogs = [];
  bool _isUpdatingStudent = false;
  bool _hasCompletedInitialSync = false;
  bool _isClearingFromCloud = false;
  double _clearProgress = 0.0;

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
  double get progress => _progress;
  double get uploadProgress => _uploadProgress;
  bool get isUploadingToCloud => _isUploadingToCloud;
  bool get isUploadComplete =>
      _hasCompletedInitialSync ||
      (!_isUploadingToCloud && _auditLogs.every((log) => log.priority == 1));
  List<AuditLog> get auditLogs => _auditLogs;
  bool get isUpdatingStudent => _isUpdatingStudent;
  bool get hasCompletedInitialSync => _hasCompletedInitialSync;
  bool get isClearingFromCloud => _isClearingFromCloud;
  double get clearProgress => _clearProgress;

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
      _isLoading = true;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      final studentsJson = prefs.getString('students');
      final columnsJson = prefs.getString('columns');
      final fileId = prefs.getString('currentFileId');
      final fileName = prefs.getString('fileName');
      if (studentsJson != null && columnsJson != null) {
        final studentsList = json.decode(studentsJson) as List;
        _students = studentsList.map((s) => Student.fromJson(s)).toList();
        _columns = List<String>.from(json.decode(columnsJson));
        _currentFileId = fileId;
        _fileName = fileName;
        _applyFilters();
        _error = null;
      } else {
        _students = [];
        _columns = [];
        _currentFileId = null;
        _fileName = null;
        _error = 'No local data found.';
      }
    } catch (e) {
      _error = 'Error loading local data: $e';
    } finally {
      _isLoading = false;
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

  // Incremental sync: only process audit logs with priority 0
  Future<void> syncToCloud(String fileName) async {
    if (!isAuthenticated) {
      _error = 'Please sign in to sync to cloud';
      notifyListeners();
      return;
    }
    try {
      _isLoading = true;
      notifyListeners();
      final user = _firebaseService.currentUser;
      if (user == null) throw Exception('User not authenticated');
      final fileId =
          _currentFileId ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
      // Only logs with priority 0 (not yet synced)
      final pendingLogs = _auditLogs.where((log) => log.priority == 0).toList();
      for (final log in pendingLogs) {
        if (log.action == 'add' || log.action == 'update') {
          final Student? student = _findStudentById(log.studentId);
          if (student != null) {
            await _firebaseService.uploadStudentsToFirestoreWithFileId([
              student,
            ], fileId);
          }
        } else if (log.action == 'delete') {
          await _firebaseService.deleteStudentFromFile(log.studentId, fileId);
        }
        // Mark as synced
        log.priority = 1;
      }
      // Sync audit logs to Firestore (limit to 10 most recent)
      await _firebaseService.syncAuditLogs(_auditLogs, user.uid, fileId);
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

  // Parse Excel file
  Future<void> parseExcelFile(Uint8List fileBytes, String fileName) async {
    try {
      _isLoading = true;
      _progress = 0.0;
      _error = null;
      notifyListeners();
      // Offload parsing to background isolate with progress callback
      final result = await compute(parseExcelInBackgroundTopLevel, {
        'fileBytes': fileBytes,
        'fileName': fileName,
      });
      _columns = List<String>.from(result['columns']);
      _students = (result['students'] as List)
          .map((rowData) => Student.fromMap(rowData, rowData['id'] as String))
          .toList();
      _fileName = fileName;
      _progress = 1.0;
      await _saveDataToLocal();
      notifyListeners(); // Data is now available in the app
      // Start background upload
      if (isAuthenticated) {
        _isUploadingToCloud = true;
        _uploadProgress = 0.0;
        notifyListeners();
        await uploadStudentsInBatches(_students, _columns, _fileName!);
        _isUploadingToCloud = false;
        _uploadProgress = 1.0;
        _hasCompletedInitialSync = true;
        notifyListeners();
      }
      _applyFilters();
      print('DEBUG: Excel parsing and local load completed successfully');
    } catch (e, stackTrace) {
      print('DEBUG: Error in parseExcelFile: $e');
      print('DEBUG: Stack trace: $stackTrace');
      _error = 'Error parsing Excel file: $e';
    } finally {
      _isLoading = false;
      _progress = 0.0;
      notifyListeners();
    }
  }

  // Upload students to Firestore in batches of 500
  Future<void> uploadStudentsInBatches(
    List<Student> students,
    List<String> columns,
    String fileName,
  ) async {
    const int batchSize = 500;
    int total = students.length;
    int uploaded = 0;
    String? fileId = _currentFileId;
    final user = _firebaseService.currentUser;
    if (user == null) return;
    // If no fileId, create one
    if (fileId == null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      fileId = 'file_$timestamp';
      _currentFileId = fileId;
    }
    // Clear existing students if updating
    if (uploaded == 0) {
      await _firebaseService.clearStudentsFromFile(fileId);
    }
    while (uploaded < total) {
      final batch = students.skip(uploaded).take(batchSize).toList();
      await _firebaseService.uploadStudentsToFirestoreWithFileId(batch, fileId);
      uploaded += batch.length;
      _uploadProgress = uploaded / total;
      print(
        'Uploading batch: $uploaded / $total, progress:  [32m$_uploadProgress [0m',
      );
      notifyListeners();
      await Future.delayed(
        Duration(milliseconds: 300),
      ); // Artificial delay for progress bar testing
    }
    // Update metadata after all batches
    await _firebaseService.updateFileMetadata(
      user.uid,
      fileId,
      columns,
      fileName,
      total,
    );
    // Ensure upload state is correct and UI is notified
    _isUploadingToCloud = false;
    _uploadProgress = 1.0;
    notifyListeners();
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
  void _ensureFileId() {
    if (_currentFileId == null || _currentFileId!.isEmpty) {
      _currentFileId = 'file_${DateTime.now().millisecondsSinceEpoch}';
      print('DEBUG: Generated new fileId:  [32m$_currentFileId [0m');
    }
  }

  Future<void> addStudent(Student student, {bool skipLogging = false}) async {
    try {
      _ensureFileId();
      print(
        'DEBUG: addStudent fileId: $_currentFileId, studentId: ${student.id}',
      );
      _students.add(student);
      await _saveDataToLocal();
      AuditLog? log;
      // Add audit log (skip for undo operations)
      if (!skipLogging) {
        log = AuditLog(
          id: 'log_${DateTime.now().millisecondsSinceEpoch}',
          action: 'add',
          studentId: student.id,
          studentName: student.name,
          newData: student.data,
          oldData: null,
          timestamp: DateTime.now(),
          userEmail: '',
          priority: 0,
        );
        _auditLogs.insert(0, log);
        notifyListeners();
        await _firebaseService.syncAuditLogs(
          _auditLogs,
          _firebaseService.currentUser?.uid ?? '',
          _currentFileId!,
        );
      }
      // Real-time sync to Firestore
      if (isAuthenticated && log != null) {
        if (_currentFileId == null) {
          _currentFileId = 'file_${DateTime.now().millisecondsSinceEpoch}';
        }
        _showSyncMessage('Syncing changes to cloud: 1 record added...');
        await _firebaseService.uploadStudentsToFirestoreWithFileId([
          student,
        ], _currentFileId!);
        log.priority = 1;
        notifyListeners();
        _showSyncMessage('1 record synced successfully.');
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
      _ensureFileId();
      print(
        'DEBUG: updateStudent fileId: $_currentFileId, studentId: ${student.id}',
      );
      _isUpdatingStudent = true;
      notifyListeners();
      final index = _students.indexWhere((s) => s.id == student.id);
      if (index != -1) {
        final oldStudent = _students[index];
        _students[index] = student;
        await _saveDataToLocal();
        AuditLog? log;
        // Add audit log (skip for undo operations)
        if (!skipLogging) {
          log = AuditLog(
            id: 'log_${DateTime.now().millisecondsSinceEpoch}',
            action: 'update',
            studentId: student.id,
            studentName: student.name,
            oldData: oldStudent.data,
            newData: student.data,
            timestamp: DateTime.now(),
            userEmail: '',
            priority: 0,
          );
          _auditLogs.insert(0, log);
          notifyListeners();
          await _firebaseService.syncAuditLogs(
            _auditLogs,
            _firebaseService.currentUser?.uid ?? '',
            _currentFileId!,
          );
        }
        // Real-time sync to Firestore
        if (isAuthenticated && log != null) {
          if (_currentFileId == null) {
            _currentFileId = 'file_${DateTime.now().millisecondsSinceEpoch}';
          }
          _showSyncMessage('Syncing changes to cloud: 1 record updated...');
          await _firebaseService.uploadStudentsToFirestoreWithFileId([
            student,
          ], _currentFileId!);
          await Future.delayed(
            const Duration(seconds: 1),
          ); // Add delay before fetching
          // Fetch the updated student from Firestore and update local list
          try {
            final latest = await _firebaseService.getStudentFromFirestore(
              student.id,
            );
            if (latest != null) {
              _students[index] = latest;
              await _saveDataToLocal();
              notifyListeners();
            }
            log.priority = 1;
            notifyListeners();
            _showSyncMessage('1 record synced successfully.');
          } catch (fetchError, stack) {
            print(
              'DEBUG: Error fetching updated student from Firestore: $fetchError',
            );
            print(stack);
            _error = 'Error fetching updated student: $fetchError';
            notifyListeners();
          }
        }
        _isUpdatingStudent = false;
        _applyFilters();
        notifyListeners();
      }
    } catch (e, stackTrace) {
      _isUpdatingStudent = false;
      print('DEBUG: Error in updateStudent: $e');
      print(stackTrace);
      _error = 'Error updating student: $e';
      notifyListeners();
    }
  }

  Future<void> deleteStudent(
    String studentId, {
    bool skipLogging = false,
  }) async {
    try {
      _ensureFileId();
      print(
        'DEBUG: deleteStudent fileId: $_currentFileId, studentId: $studentId',
      );
      final studentToDelete = _students.firstWhere((s) => s.id == studentId);
      _students.removeWhere((s) => s.id == studentId);
      await _saveDataToLocal();
      AuditLog? log;
      // Add audit log (skip for undo operations)
      if (!skipLogging) {
        log = AuditLog(
          id: 'log_${DateTime.now().millisecondsSinceEpoch}',
          action: 'delete',
          studentId: studentId,
          studentName: studentToDelete.name,
          oldData: studentToDelete.data,
          newData: null,
          timestamp: DateTime.now(),
          userEmail: '',
          priority: 0,
        );
        _auditLogs.insert(0, log);
        notifyListeners();
        await _firebaseService.syncAuditLogs(
          _auditLogs,
          _firebaseService.currentUser?.uid ?? '',
          _currentFileId!,
        );
      }
      // Real-time sync to Firestore
      if (isAuthenticated && log != null) {
        if (_currentFileId == null) {
          _currentFileId = 'file_${DateTime.now().millisecondsSinceEpoch}';
        }
        _showSyncMessage('Syncing changes to cloud: 1 record deleted...');
        await _firebaseService.deleteStudentFromFile(
          studentId,
          _currentFileId!,
        );
        log.priority = 1;
        notifyListeners();
        _showSyncMessage('1 record synced successfully.');
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
    _isClearingFromCloud = true;
    _clearProgress = 0.0;
    notifyListeners();
    try {
      await _firebaseService.deleteAllStudentsFromFirestore(
        onProgress: (deleted, total) {
          _clearProgress = total == 0 ? 1.0 : deleted / total;
          notifyListeners();
        },
      );
      _clearProgress = 1.0;
    } catch (e) {
      _error = 'Error clearing data from Firestore: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isClearingFromCloud = false;
      notifyListeners();
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

  Student? _findStudentById(String id) {
    for (final s in _students) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _showSyncMessage(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.blue,
      textColor: Colors.white,
    );
  }
}

// Top-level function for compute (must be outside any class)
Map<String, dynamic> parseExcelInBackgroundTopLevel(Map<String, dynamic> args) {
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
  // Extract and sanitize headers from first row
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
    // Sanitize: replace invalid Firestore chars and skip empty
    columnName = columnName.replaceAll(RegExp(r'[\.$\[\]/#]'), '_');
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
