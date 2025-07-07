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

  // Parse Excel file
  Future<void> parseExcelFile(Uint8List fileBytes, String fileName) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('DEBUG: Starting Excel parsing for file: $fileName');
      print('DEBUG: File size: ${fileBytes.length} bytes');

      // Validate file size
      if (fileBytes.length == 0) {
        _error = 'Excel file is empty';
        return;
      }

      // Check file size (warn if > 10MB)
      if (fileBytes.length > 10 * 1024 * 1024) {
        print(
          'DEBUG: Large file detected (${(fileBytes.length / 1024 / 1024).toStringAsFixed(1)}MB)',
        );
      }

      // Check if file has Excel signature
      if (fileBytes.length < 4) {
        _error = 'File is too small to be a valid Excel file';
        return;
      }

      // Check for Excel file signatures
      final signature = fileBytes.take(4).toList();
      final isXlsx =
          signature[0] == 0x50 && signature[1] == 0x4B; // PK (ZIP signature)

      if (!isXlsx) {
        print('DEBUG: File does not appear to be a valid XLSX file');
        print(
          'DEBUG: File signature: ${signature.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
        );
        // Continue anyway as the Excel package might still be able to handle it
      } else {
        print('DEBUG: File appears to be a valid XLSX file');
      }

      print('DEBUG: About to decode Excel file...');
      Excel? excel;

      // Try to decode the Excel file with better error handling
      try {
        excel = Excel.decodeBytes(fileBytes);
        print('DEBUG: Excel file decoded successfully');
      } catch (e) {
        print('DEBUG: First attempt failed, trying alternative approach...');

        // Try alternative approach - create a new Excel instance first
        try {
          excel = Excel.createExcel();
          // Try to decode again
          excel = Excel.decodeBytes(fileBytes);
          print('DEBUG: Excel file decoded successfully on second attempt');
        } catch (e2) {
          print('DEBUG: Second attempt also failed: $e2');
        }

        print('DEBUG: Error decoding Excel file: $e');

        // Try to provide more specific error messages based on the error type
        if (e.toString().contains('Null check operator')) {
          _error =
              'Excel file parsing error detected.\n\n'
              'This specific file appears to have a format that the Excel parser cannot handle properly. '
              'This is a known issue with some Excel files, especially those with:\n'
              '• Complex formatting\n'
              '• Merged cells\n'
              '• Special characters\n'
              '• Large datasets\n\n'
              'Please try the following solutions:\n'
              '1. Open the file in Excel and save it as a new .xlsx file\n'
              '2. Remove any merged cells or complex formatting\n'
              '3. Try exporting the data as CSV and then converting to Excel\n'
              '4. Use a different Excel file with simpler formatting\n\n'
              'If the problem persists, please contact support with the file details.';
        } else {
          _error =
              'Unable to parse Excel file: $e\n\n'
              'Please ensure the file is a valid Excel (.xlsx) file and try again.';
        }
        return;
      }

      if (excel == null || excel.tables.isEmpty) {
        _error = 'Excel file is invalid or corrupted';
        return;
      }

      final sheetNames = excel.tables.keys.toList();
      print('DEBUG: Found ${sheetNames.length} sheets: $sheetNames');

      if (sheetNames.isEmpty) {
        _error = 'Excel file contains no sheets';
        return;
      }

      print('DEBUG: About to access sheet: ${sheetNames.first}');
      final sheet = excel.tables[sheetNames.first];
      print('DEBUG: Sheet accessed successfully');

      if (sheet == null) {
        _error = 'Could not access the first sheet';
        return;
      }

      print(
        'DEBUG: Successfully decoded Excel file with ${sheetNames.length} sheets',
      );
      print('DEBUG: Using sheet: ${sheetNames.first}');

      print(
        'DEBUG: Sheet dimensions - Rows: ${sheet.maxRows}, Columns: ${sheet.maxColumns}',
      );

      if (sheet.maxRows == 0) {
        _error = 'Excel file is empty';
        return;
      }

      // Warn about very large datasets
      if (sheet.maxRows > 50000) {
        print('DEBUG: Very large dataset detected: ${sheet.maxRows} rows');
      }

      // Extract headers from first row with null safety
      _columns = [];
      print('DEBUG: About to access header row...');
      final headerRow = sheet.row(0);
      print('DEBUG: Header row accessed successfully');
      print('DEBUG: Header row length: [38;5;2m${headerRow.length}[0m');

      // Generate headers, using default names for missing/empty
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
        _columns.add(columnName);
      }
      print('DEBUG: Extracted ${_columns.length} columns: $_columns');

      // Parse data rows with progress tracking
      _students = [];
      final totalRows = sheet.maxRows;
      int processedRows = 0;
      print('DEBUG: Starting to process $totalRows rows');
      for (int row = 1; row < totalRows; row++) {
        try {
          final rowData = <String, dynamic>{};
          bool hasData = false;
          final currentRow = sheet.row(row);
          for (int col = 0; col < _columns.length; col++) {
            String value = '';
            if (col < currentRow.length) {
              final cellValue = currentRow[col];
              if (cellValue != null && cellValue.value != null) {
                value = cellValue.value.toString().trim();
                if (value.isNotEmpty) hasData = true;
              }
            }
            rowData[_columns[col]] = value;
          }
          if (hasData) {
            final studentId =
                'row_${row}_${DateTime.now().millisecondsSinceEpoch}';
            _students.add(Student.fromMap(rowData, studentId));
          }
          processedRows++;
          if (processedRows % 1000 == 0) {
            print('DEBUG: Processed $processedRows/$totalRows rows');
            notifyListeners();
          }
        } catch (rowError) {
          print('DEBUG: Error processing row $row: $rowError');
          continue;
        }
      }
      print(
        'DEBUG: Successfully processed ${_students.length} students from $processedRows rows',
      );
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
