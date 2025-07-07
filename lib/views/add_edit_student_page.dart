import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/student_viewmodel.dart';
import '../models/student.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AddEditStudentPage extends StatefulWidget {
  final String? studentId;

  const AddEditStudentPage({super.key, this.studentId});

  @override
  State<AddEditStudentPage> createState() => _AddEditStudentPageState();
}

class _AddEditStudentPageState extends State<AddEditStudentPage> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, TextEditingController> _controllers;
  bool _controllersInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controllersInitialized) {
      _initializeControllers();
      _controllersInitialized = true;
    }
  }

  void _initializeControllers() {
    final viewModel = Provider.of<StudentViewModel>(context, listen: false);
    _controllers = {};

    if (viewModel.columns.isEmpty) {
      print('DEBUG: No columns available for form initialization');
      return;
    }

    for (String column in viewModel.columns) {
      String initialValue = '';
      if (widget.studentId != null) {
        final student = viewModel.getStudentById(widget.studentId!);
        if (student != null) {
          initialValue = student.data[column]?.toString() ?? '';
        }
      }
      _controllers[column] = TextEditingController(text: initialValue);
      // Add listeners for total and paid fees to update pending fees
      if (column.toLowerCase().contains('total') ||
          column.toLowerCase().contains('paid')) {
        _controllers[column]!.addListener(() {
          setState(() {});
        });
      }
    }
  }

  @override
  void dispose() {
    _controllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studentId != null ? 'Edit Student' : 'Add Student'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Consumer<StudentViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.columns.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text('No data structure available'),
                  const SizedBox(height: 8),
                  const Text('Please upload an Excel file first'),
                ],
              ),
            );
          }

          // Check if controllers are initialized
          if (_controllers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing form...'),
                ],
              ),
            );
          }

          // Only show editable fields that are not calculated (exclude revenue fields)
          final editableColumns = viewModel.columns
              .where(
                (col) =>
                    !col.toLowerCase().contains('revenue') &&
                    !col.toLowerCase().contains('pending'),
              )
              .toList();

          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 24),
                        ...editableColumns.map((column) => _buildField(column)),
                        _buildPendingFeesField(viewModel),
                      ],
                    ),
                  ),
                ),
                _buildBottomBar(context, viewModel),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              widget.studentId != null ? Icons.edit : Icons.person_add,
              color: Colors.blue.shade700,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.studentId != null
                        ? 'Edit Student'
                        : 'Add New Student',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.studentId != null
                        ? 'Update student information'
                        : 'Fill in the student details below',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String column) {
    final isRequired = _isRequiredField(column);
    final isPaidFees =
        column.toLowerCase().contains('paid') &&
        column.toLowerCase().contains('fee');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[column],
        decoration: InputDecoration(
          labelText: column,
          hintText: 'Enter ${column.toLowerCase()}',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey.shade50,
          prefixIcon: _getFieldIcon(column),
          suffixIcon: isRequired
              ? const Icon(Icons.star, color: Colors.red, size: 16)
              : null,
        ),
        validator: (value) {
          if (isRequired && (value == null || value.trim().isEmpty)) {
            return '$column is required';
          }

          // Validate paid fees don't exceed total fees
          if (isPaidFees) {
            final paidAmount = double.tryParse(value ?? '') ?? 0.0;
            final totalFeesColumn = _getTotalFeesColumn();
            if (totalFeesColumn.isNotEmpty) {
              final totalAmount =
                  double.tryParse(_controllers[totalFeesColumn]?.text ?? '') ??
                  0.0;
              if (paidAmount > totalAmount) {
                return 'Paid fees cannot exceed total fees (₹${totalAmount.toStringAsFixed(0)})';
              }
            }
          }

          return null;
        },
        keyboardType: _getKeyboardType(column),
        onChanged: (value) {
          // Update pending fees when total or paid fees change
          if (column.toLowerCase().contains('total') ||
              column.toLowerCase().contains('paid')) {
            setState(() {});
          }
        },
      ),
    );
  }

  bool _isRequiredField(String column) {
    final requiredFields = ['student name', 'name'];
    return requiredFields.any(
      (field) => column.toLowerCase().contains(field.toLowerCase()),
    );
  }

  Icon _getFieldIcon(String column) {
    final lowerColumn = column.toLowerCase();

    if (lowerColumn.contains('name')) {
      return const Icon(Icons.person);
    } else if (lowerColumn.contains('school')) {
      return const Icon(Icons.school);
    } else if (lowerColumn.contains('division')) {
      return const Icon(Icons.category);
    } else if (lowerColumn.contains('fee')) {
      return const Icon(Icons.currency_rupee);
    } else if (lowerColumn.contains('phone')) {
      return const Icon(Icons.phone);
    } else if (lowerColumn.contains('email')) {
      return const Icon(Icons.email);
    } else if (lowerColumn.contains('address')) {
      return const Icon(Icons.location_on);
    } else {
      return const Icon(Icons.edit);
    }
  }

  TextInputType _getKeyboardType(String column) {
    final lowerColumn = column.toLowerCase();

    if (lowerColumn.contains('phone')) {
      return TextInputType.phone;
    } else if (lowerColumn.contains('email')) {
      return TextInputType.emailAddress;
    } else if (lowerColumn.contains('fee') || lowerColumn.contains('amount')) {
      return TextInputType.number;
    } else {
      return TextInputType.text;
    }
  }

  String _getTotalFeesColumn() {
    final viewModel = Provider.of<StudentViewModel>(context, listen: false);
    return viewModel.columns.firstWhere(
      (col) =>
          col.toLowerCase().contains('total') &&
          col.toLowerCase().contains('fee'),
      orElse: () => '',
    );
  }

  Widget _buildBottomBar(BuildContext context, StudentViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _saveStudent(viewModel),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(widget.studentId != null ? 'Update' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }

  void _saveStudent(StudentViewModel viewModel) async {
    if (_formKey.currentState?.validate() ?? false) {
      Map<String, dynamic> studentData = {};

      for (String column in viewModel.columns) {
        studentData[column] = _controllers[column]?.text ?? '';
      }

      try {
        // Recalculate pending fees before saving
        final totalFeesColumn = viewModel.columns.firstWhere(
          (col) => col.toLowerCase().contains('total'),
          orElse: () => '',
        );
        final paidFeesColumn = viewModel.columns.firstWhere(
          (col) => col.toLowerCase().contains('paid'),
          orElse: () => '',
        );
        double total =
            double.tryParse(_controllers[totalFeesColumn]?.text ?? '') ?? 0.0;
        double paid =
            double.tryParse(_controllers[paidFeesColumn]?.text ?? '') ?? 0.0;
        double pending = total - paid;
        // Find the pending fees column if it exists, else use a default
        String pendingFeesColumn = viewModel.columns.firstWhere(
          (col) =>
              col.toLowerCase().contains('pending') ||
              col.toLowerCase().contains('balance') ||
              col.toLowerCase().contains('due'),
          orElse: () => 'Pending Fees',
        );
        studentData[pendingFeesColumn] = pending.toStringAsFixed(0);

        if (widget.studentId != null) {
          final existingStudent = viewModel.getStudentById(widget.studentId!);
          if (existingStudent != null) {
            final updatedStudent = existingStudent.copyWith(data: studentData);
            await viewModel.updateStudent(updatedStudent);
          }
        } else {
          final newStudent = Student.fromMap(
            studentData,
            DateTime.now().millisecondsSinceEpoch.toString(),
          );
          await viewModel.addStudent(newStudent);
        }
        if (mounted) {
          Fluttertoast.showToast(
            msg: widget.studentId != null
                ? 'Student updated successfully'
                : 'Student added successfully',
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }
        Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          Fluttertoast.showToast(
            msg: 'Failed to save student: $e',
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
        }
      }
    }
  }

  Widget _buildPendingFeesField(StudentViewModel viewModel) {
    final totalFeesColumn = viewModel.columns.firstWhere(
      (col) => col.toLowerCase().contains('total'),
      orElse: () => '',
    );
    final paidFeesColumn = viewModel.columns.firstWhere(
      (col) => col.toLowerCase().contains('paid'),
      orElse: () => '',
    );
    double total =
        double.tryParse(_controllers[totalFeesColumn]?.text ?? '') ?? 0.0;
    double paid =
        double.tryParse(_controllers[paidFeesColumn]?.text ?? '') ?? 0.0;
    double pending = total - paid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        readOnly: true,
        decoration: InputDecoration(
          labelText: 'Pending Fees',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey.shade100,
          prefixIcon: const Icon(Icons.currency_rupee),
        ),
        controller: TextEditingController(
          text: '₹${pending.toStringAsFixed(0)}',
        ),
        enabled: false,
      ),
    );
  }
}
