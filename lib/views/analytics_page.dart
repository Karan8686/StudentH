import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/student_viewmodel.dart';
import '../services/audit_service.dart';
import '../models/audit_log.dart';
import '../models/student.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String? selectedStandard;
  String? selectedYear;
  final AuditService _auditService = AuditService();
  List<AuditLog> _auditLogs = [];
  bool _isLoadingLogs = false;

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _isLoadingLogs = true;
    });

    try {
      final logs = await _auditService.getLogs();
      setState(() {
        _auditLogs = logs;
      });
    } catch (e) {
      print('Error loading audit logs: $e');
    } finally {
      setState(() {
        _isLoadingLogs = false;
      });
    }
  }

  Future<void> _undoAction(AuditLog log) async {
    final viewModel = Provider.of<StudentViewModel>(context, listen: false);

    try {
      switch (log.action) {
        case 'add':
          // Undo add: delete the student (skip logging)
          await viewModel.deleteStudent(log.studentId, skipLogging: true);
          break;
        case 'update':
          // Undo update: restore old data (skip logging)
          if (log.oldData != null) {
            final oldStudent = Student.fromMap(log.oldData!, log.studentId);
            await viewModel.updateStudent(oldStudent, skipLogging: true);
          }
          break;
        case 'delete':
          // Undo delete: restore the student (skip logging)
          if (log.oldData != null) {
            final restoredStudent = Student.fromMap(
              log.oldData!,
              log.studentId,
            );
            await viewModel.addStudent(restoredStudent, skipLogging: true);
          }
          break;
      }

      // Reload audit logs
      await _loadAuditLogs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Undo successful: ${log.actionDisplay} ${log.studentName}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error undoing action: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Consumer<StudentViewModel>(
        builder: (context, viewModel, child) {
          final students = viewModel.students;
          if (students.isEmpty) {
            return const Center(
              child: Text(
                'No data available. Please upload an Excel file.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          // Dynamically detect columns
          final columns = students.first.data.keys.toList();
          String? schoolCol = columns.firstWhere(
            (c) => c.toLowerCase().contains('school'),
            orElse: () => '',
          );
          String? monthCol = columns.firstWhere(
            (c) => c.toLowerCase().contains('month'),
            orElse: () => '',
          );
          String? yearCol = columns.firstWhere(
            (c) => c.toLowerCase().contains('year'),
            orElse: () => '',
          );

          // Get unique filter values
          final schools = <String>{};
          final months = <String>{};
          final years = <String>{};
          for (final s in students) {
            if (schoolCol.isNotEmpty) {
              final val = s.data[schoolCol]?.toString() ?? '';
              if (val.isNotEmpty) schools.add(val);
            }
            if (monthCol.isNotEmpty) {
              final val = s.data[monthCol]?.toString() ?? '';
              if (val.isNotEmpty) months.add(val);
            }
            if (yearCol.isNotEmpty) {
              final val = s.data[yearCol]?.toString() ?? '';
              if (val.isNotEmpty) years.add(val);
            }
          }

          // State for filters
          String? selectedSchool;
          String? selectedMonth;
          String? selectedYear;

          // Use StatefulBuilder to manage filter state locally
          return StatefulBuilder(
            builder: (context, setState) {
              // Filter students
              final filtered = students.where((s) {
                final schoolOk =
                    schoolCol.isEmpty ||
                    selectedSchool == null ||
                    selectedSchool == '' ||
                    s.data[schoolCol]?.toString() == selectedSchool;
                final monthOk =
                    monthCol.isEmpty ||
                    selectedMonth == null ||
                    selectedMonth == '' ||
                    s.data[monthCol]?.toString() == selectedMonth;
                final yearOk =
                    yearCol.isEmpty ||
                    selectedYear == null ||
                    selectedYear == '' ||
                    s.data[yearCol]?.toString() == selectedYear;
                return schoolOk && monthOk && yearOk;
              }).toList();

              // Calculate total income
              double totalIncome = 0.0;
              for (final s in filtered) {
                // Find the paid fees column dynamically
                String? paidCol = columns.firstWhere(
                  (c) => c.toLowerCase().contains('paid'),
                  orElse: () => '',
                );
                if (paidCol != null && paidCol.isNotEmpty) {
                  totalIncome +=
                      double.tryParse(s.data[paidCol]?.toString() ?? '') ?? 0.0;
                }
              }

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Always show overall total income
                    Text(
                      'Overall Total Income: ₹${students.fold<double>(0.0, (sum, s) {
                        String? paidCol = columns.firstWhere((c) => c.toLowerCase().contains('paid'), orElse: () => '');
                        if (paidCol != null && paidCol.isNotEmpty) {
                          return sum + (double.tryParse(s.data[paidCol]?.toString() ?? '') ?? 0.0);
                        }
                        return sum;
                      }).toStringAsFixed(2)}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (schoolCol.isNotEmpty && schools.isNotEmpty)
                      DropdownButton<String>(
                        value: selectedSchool,
                        hint: const Text('Select School'),
                        items: schools
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => selectedSchool = val),
                      ),
                    if (monthCol.isNotEmpty &&
                        months.isNotEmpty &&
                        selectedSchool != null)
                      DropdownButton<String>(
                        value: selectedMonth,
                        hint: const Text('Select Month'),
                        items:
                            [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('All Months'),
                              ),
                            ] +
                            months
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) => setState(() => selectedMonth = val),
                      ),
                    if (yearCol.isNotEmpty &&
                        years.isNotEmpty &&
                        selectedSchool != null)
                      DropdownButton<String>(
                        value: selectedYear,
                        hint: const Text('Select Year'),
                        items:
                            [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('All Years'),
                              ),
                            ] +
                            years
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(y),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) => setState(() => selectedYear = val),
                      ),
                    if (selectedSchool == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: Center(
                          child: Text(
                            'Please select a school to view analytics.',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ),
                      ),
                    if (selectedSchool != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Filtered Total Income: ₹${totalIncome.toStringAsFixed(2)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, idx) {
                            final s = filtered[idx];
                            return Card(
                              child: ListTile(
                                title: Text(s.name),
                                subtitle: Text(
                                  s.data[schoolCol]?.toString() ?? '',
                                ),
                                trailing: Text(
                                  () {
                                    double paid = 0.0;
                                    if (columns.any(
                                      (c) => c.toLowerCase().contains('paid'),
                                    )) {
                                      final paidCol = columns.firstWhere(
                                        (c) => c.toLowerCase().contains('paid'),
                                      );
                                      paid =
                                          double.tryParse(
                                            s.data[paidCol]?.toString() ?? '',
                                          ) ??
                                          0.0;
                                    }
                                    return '₹${paid.toStringAsFixed(2)}';
                                  }(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    // Always show audit logs section
                    _buildAuditLogsSection(),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAuditLogsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                if (_auditLogs.isNotEmpty)
                  IconButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear Activity Log'),
                          content: const Text(
                            'Are you sure you want to clear all activity logs?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await _auditService.clearLogs();
                        await _loadAuditLogs();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Activity logs cleared'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.clear_all),
                    tooltip: 'Clear all logs',
                    color: Colors.red.shade600,
                  ),
                IconButton(
                  onPressed: _loadAuditLogs,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoadingLogs)
          const Center(child: CircularProgressIndicator())
        else if (_auditLogs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.history, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'No recent activity',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _auditLogs.length,
            itemBuilder: (context, index) {
              final log = _auditLogs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getActionColor(log.action),
                    child: Icon(
                      _getActionIcon(log.action),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    '${log.actionDisplay} ${log.studentName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.timeAgo),
                      if (log.action == 'update')
                        Text(
                          'Updated student information',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  trailing:
                      log.action !=
                          'add' // Can't undo add operations
                      ? IconButton(
                          onPressed: () => _undoAction(log),
                          icon: const Icon(Icons.undo),
                          tooltip: 'Undo',
                          color: Colors.orange.shade600,
                        )
                      : null,
                ),
              );
            },
          ),
      ],
    );
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'add':
        return Colors.green;
      case 'update':
        return Colors.blue;
      case 'delete':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'add':
        return Icons.add;
      case 'update':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      default:
        return Icons.info;
    }
  }
}
