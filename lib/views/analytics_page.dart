import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/student_viewmodel.dart';
import '../services/audit_service.dart';
import '../models/audit_log.dart';
import '../models/student.dart';
import 'package:intl/intl.dart';
import 'package:flutter/rendering.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with AutomaticKeepAliveClientMixin {
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

  @override
  bool get wantKeepAlive => true;

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
    return Consumer<StudentViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isUploadingToCloud) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_upload, size: 64, color: Colors.blue),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    value: viewModel.uploadProgress,
                    minHeight: 10,
                    backgroundColor: Colors.blue.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Uploading to cloud: ${(viewModel.uploadProgress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Data is being synced to the cloud. Please do not close the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blueGrey, fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        }
        if (!viewModel.isUploadComplete) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 64, color: Colors.grey),
                const SizedBox(height: 24),
                const Text(
                  'Analytics will be available after all data is uploaded to the cloud.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }
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

        // If no month/year columns, try to extract from a date column
        String? dateCol = columns.firstWhere(
          (c) => c.toLowerCase().contains('date'),
          orElse: () => '',
        );

        final schools = <String>{};
        final months = <String>{};
        final years = <String>{};
        for (final s in students) {
          if (schoolCol.isNotEmpty) {
            final val = s.data[schoolCol]?.toString() ?? '';
            if (val.isNotEmpty) schools.add(val);
          }
          // Extract month/year from monthCol/yearCol or from dateCol
          DateTime? date;
          final dateStr = s.data[dateCol]?.toString() ?? '';
          if (dateStr.isNotEmpty) {
            date = DateTime.tryParse(dateStr);
            if (date == null) {
              // Try DD/MM/YYYY
              try {
                date = DateFormat('dd/MM/yyyy').parseStrict(dateStr);
              } catch (_) {}
            }
            if (date == null) {
              // Try MM/DD/YYYY
              try {
                date = DateFormat('MM/dd/yyyy').parseStrict(dateStr);
              } catch (_) {}
            }
          }
          if (date != null) {
            months.add('${date.month}'.padLeft(2, '0'));
            years.add('${date.year}');
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
              // Month/year filter: check monthCol/yearCol or extract from dateCol
              bool monthOk = true;
              bool yearOk = true;
              if (selectedMonth != null && selectedMonth != '') {
                if (monthCol.isNotEmpty) {
                  monthOk = s.data[monthCol]?.toString() == selectedMonth;
                } else if (dateCol.isNotEmpty) {
                  final dateStr = s.data[dateCol]?.toString() ?? '';
                  if (dateStr.isNotEmpty) {
                    final date = DateTime.tryParse(dateStr);
                    monthOk =
                        date != null &&
                        '${date.month}'.padLeft(2, '0') == selectedMonth;
                  }
                }
              }
              if (selectedYear != null && selectedYear != '') {
                if (yearCol.isNotEmpty) {
                  yearOk = s.data[yearCol]?.toString() == selectedYear;
                } else if (dateCol.isNotEmpty) {
                  final dateStr = s.data[dateCol]?.toString() ?? '';
                  if (dateStr.isNotEmpty) {
                    final date = DateTime.tryParse(dateStr);
                    yearOk = date != null && '${date.year}' == selectedYear;
                  }
                }
              }
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

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overall Total Income Card
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bar_chart,
                          color: Colors.blue.shade700,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Overall Total Income: ₹${students.fold<double>(0.0, (sum, s) {
                              String? paidCol = columns.firstWhere((c) => c.toLowerCase().contains('paid'), orElse: () => '');
                              if (paidCol != null && paidCol.isNotEmpty) {
                                return sum + (double.tryParse(s.data[paidCol]?.toString() ?? '') ?? 0.0);
                              }
                              return sum;
                            }).toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Filters Card
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (schoolCol.isNotEmpty && schools.isNotEmpty)
                          DropdownButton<String>(
                            isExpanded: true,
                            value: selectedSchool,
                            hint: const Text('Select School'),
                            dropdownColor: Colors.white,
                            iconEnabledColor: Colors.blue.shade700,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.blue.shade700),
                            items: schools
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      s,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Colors.blue.shade700,
                                          ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => selectedSchool = val),
                          ),
                        if (monthCol.isNotEmpty &&
                            months.isNotEmpty &&
                            selectedSchool != null)
                          DropdownButton<String>(
                            isExpanded: true,
                            value: selectedMonth,
                            hint: const Text('Select Month'),
                            dropdownColor: Colors.white,
                            iconEnabledColor: Colors.blue.shade700,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.blue.shade700),
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
                                        child: Text(
                                          m,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.blue.shade700,
                                              ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (val) =>
                                setState(() => selectedMonth = val),
                          ),
                        if (yearCol.isNotEmpty &&
                            years.isNotEmpty &&
                            selectedSchool != null)
                          DropdownButton<String>(
                            isExpanded: true,
                            value: selectedYear,
                            hint: const Text('Select Year'),
                            dropdownColor: Colors.white,
                            iconEnabledColor: Colors.blue.shade700,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.blue.shade700),
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
                                        child: Text(
                                          y,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.blue.shade700,
                                              ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (val) =>
                                setState(() => selectedYear = val),
                          ),
                      ],
                    ),
                  ),
                  if (selectedSchool == null)
                    Container(
                      margin: const EdgeInsets.only(top: 32),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Center(
                        child: Text(
                          'Please select a school to view analytics.',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  if (selectedSchool != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            itemBuilder: (context, idx) {
                              final s = filtered[idx];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: ListTile(
                                  title: Text(
                                    s.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
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
                                          (c) =>
                                              c.toLowerCase().contains('paid'),
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
                        ],
                      ),
                    ),
                  ],
                  // Always show audit logs section
                  _buildAuditLogsSection(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAuditLogsSection() {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.history, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Recent Activity',
                    style: textTheme.titleMedium?.copyWith(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
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
                    icon: Icon(Icons.refresh, color: Colors.blue.shade700),
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
            Padding(
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
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _auditLogs.length,
              itemBuilder: (context, index) {
                final log = _auditLogs[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
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
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
                    trailing: log.action != 'add'
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
      ),
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
