import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _excelDataKey = 'excel_data';
  static const String _columnsKey = 'excel_columns';
  static const String _fileNameKey = 'excel_filename';

  // Save Excel data
  static Future<void> saveExcelData(
    List<Map<String, dynamic>> students,
    List<String> columns,
    String fileName,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Convert students to JSON
    final studentsJson = students.map((student) => student).toList();

    await prefs.setString(_excelDataKey, jsonEncode(studentsJson));
    await prefs.setStringList(_columnsKey, columns);
    await prefs.setString(_fileNameKey, fileName);
  }

  // Load Excel data
  static Future<Map<String, dynamic>?> loadExcelData() async {
    final prefs = await SharedPreferences.getInstance();

    final studentsJson = prefs.getString(_excelDataKey);
    final columns = prefs.getStringList(_columnsKey);
    final fileName = prefs.getString(_fileNameKey);

    if (studentsJson != null && columns != null) {
      final students = jsonDecode(studentsJson) as List;
      final studentsList = students.cast<Map<String, dynamic>>();

      return {
        'students': studentsList,
        'columns': columns,
        'fileName': fileName ?? '',
      };
    }

    return null;
  }

  // Clear all data
  static Future<void> clearData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_excelDataKey);
    await prefs.remove(_columnsKey);
    await prefs.remove(_fileNameKey);
  }

  // Check if data exists
  static Future<bool> hasData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_excelDataKey);
  }
}
