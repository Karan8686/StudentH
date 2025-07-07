import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/student_viewmodel.dart';
import '../views/add_edit_student_page.dart';

class StudentDetailPage extends StatelessWidget {
  final String studentId;

  const StudentDetailPage({super.key, required this.studentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Details'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          Consumer<StudentViewModel>(
            builder: (context, viewModel, child) {
              final student = viewModel.getStudentById(studentId);
              if (student != null) {
                return PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AddEditStudentPage(studentId: studentId),
                          ),
                        );
                        break;
                      case 'delete':
                        _showDeleteDialog(context, viewModel, student);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<StudentViewModel>(
        builder: (context, viewModel, child) {
          final student = viewModel.getStudentById(studentId);

          if (student == null) {
            return const Center(child: Text('Student not found'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, student),
                const SizedBox(height: 24),
                _buildPersonalInfo(context, student),
                const SizedBox(height: 24),
                _buildFeeInfo(context, student),
                const SizedBox(height: 24),
                _buildAllData(context, student, viewModel),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, student) {
    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blue.shade100,
            child: Text(
              student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 32,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            student.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (student.school.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              student.school,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPersonalInfo(BuildContext context, student) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal Information',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Name', student.name),
            if (student.school.isNotEmpty)
              _buildInfoRow('School', student.school),
            if (student.division.isNotEmpty)
              _buildInfoRow('Division', student.division),
          ],
        ),
      ),
    );
  }

  Widget _buildFeeInfo(BuildContext context, student) {
    final totalFees = student.totalFeesAmount;
    final paidFees = student.paidFeesAmount;
    final pendingFees = student.pendingFeesAmount;
    final progress = totalFees > 0 ? paidFees / totalFees : 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fee Information',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Total Fees', '₹${totalFees.toStringAsFixed(0)}'),
            _buildInfoRow('Paid Fees', '₹${paidFees.toStringAsFixed(0)}'),
            _buildInfoRow('Pending Fees', '₹${pendingFees.toStringAsFixed(0)}'),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payment Progress',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: progress >= 1.0 ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress >= 1.0 ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllData(
    BuildContext context,
    student,
    StudentViewModel viewModel,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All Data',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...viewModel.columns.map(
              (column) =>
                  _buildInfoRow(column, student.data[column]?.toString() ?? ''),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not specified' : value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    StudentViewModel viewModel,
    student,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student'),
        content: Text('Are you sure you want to delete ${student.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              viewModel.deleteStudent(studentId);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
