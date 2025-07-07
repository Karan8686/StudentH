import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../viewmodels/teacher_viewmodel.dart';
import 'teacher_detail_page.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';

class TeachersPage extends StatefulWidget {
  const TeachersPage({Key? key}) : super(key: key);
  @override
  State<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends State<TeachersPage> {
  final Map<String, List<Lecture>> _lectures = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTeachersAndLectures();
  }

  Future<void> _loadTeachersAndLectures() async {
    final viewModel = Provider.of<TeacherViewModel>(context, listen: false);
    await viewModel.loadTeachers();
    final teachers = viewModel.teachers;
    final firebaseService = FirebaseService();
    Map<String, List<Lecture>> lecturesMap = {};
    for (final teacher in teachers) {
      final lectures = await firebaseService.getLectures(teacher.id);
      lecturesMap[teacher.id] = lectures;
    }
    setState(() {
      _lectures.clear();
      _lectures.addAll(lecturesMap);
    });
  }

  Future<void> _refreshTeachers() async {
    await _loadTeachersAndLectures();
  }

  void _showAddOrEditTeacherDialog({Teacher? teacher}) {
    final nameController = TextEditingController(text: teacher?.name ?? '');
    final subjectsController = TextEditingController(
      text: teacher?.subjects.join(' ') ?? '',
    );
    final rateController = TextEditingController(
      text: teacher?.perHourRate.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final isEdit = teacher != null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(isEdit ? 'Edit Teacher' : 'Add Teacher'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: subjectsController,
                  decoration: const InputDecoration(
                    labelText: 'Subjects (space separated)',
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: rateController,
                  decoration: const InputDecoration(
                    labelText: 'Per Hour Rate (₹)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Required';
                    final d = double.tryParse(val);
                    if (d == null || d <= 0) return 'Enter a valid rate';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      if (formKey.currentState?.validate() ?? false) {
                        setState(() => _isSaving = true);
                        setStateDialog(() {});
                        final name = nameController.text.trim();
                        final subjects = subjectsController.text
                            .split(' ')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                        final rate =
                            double.tryParse(rateController.text.trim()) ?? 0.0;
                        final newTeacher = Teacher(
                          id:
                              teacher?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          name: name,
                          subjects: subjects,
                          perHourRate: rate,
                        );
                        final viewModel = Provider.of<TeacherViewModel>(
                          context,
                          listen: false,
                        );
                        try {
                          if (isEdit) {
                            await viewModel.updateTeacher(newTeacher);
                          } else {
                            await viewModel.addTeacher(newTeacher);
                            setState(() {
                              _lectures[newTeacher.id] = [];
                            });
                          }
                          Navigator.pop(context);
                        } catch (e) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        } finally {
                          setState(() => _isSaving = false);
                        }
                      }
                    },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTeacher(BuildContext context, Teacher teacher) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Teacher'),
        content: Text('Are you sure you want to delete ${teacher.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        setState(() => _isSaving = true);
        await Provider.of<TeacherViewModel>(
          context,
          listen: false,
        ).deleteTeacher(teacher.id);
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Teacher deleted')));
      } catch (e) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting teacher: $e')));
      }
    }
  }

  double _teacherTotalSalary(String teacherId) {
    final lectures = _lectures[teacherId] ?? [];
    return lectures.fold(0.0, (sum, l) => sum + l.amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Consumer<TeacherViewModel>(
      builder: (context, viewModel, child) {
        final teachers = viewModel.teachers;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Teachers',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            elevation: 2,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (viewModel.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    viewModel.error!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              if (viewModel.isLoading) _buildShimmerLoader(theme),
              if (!viewModel.isLoading && teachers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No teachers yet. Tap + to add.',
                    style: textTheme.bodyLarge,
                  ),
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'All Teachers',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: teachers.length,
                  padding: const EdgeInsets.only(bottom: 80),
                  itemBuilder: (context, idx) {
                    final teacher = teachers[idx];
                    final totalSalary = _teacherTotalSalary(teacher.id);
                    final lectures = _lectures[teacher.id] ?? [];
                    final color = colorScheme.primary.withOpacity(
                      0.8 - (idx % 3) * 0.2,
                    );
                    return GestureDetector(
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TeacherDetailPage(
                              teacher: teacher,
                              lectures: List<Lecture>.from(
                                _lectures[teacher.id] ?? [],
                              ),
                              onLecturesUpdated: (teacherId, updatedLectures) {
                                setState(() {
                                  _lectures[teacherId] = updatedLectures;
                                });
                              },
                            ),
                          ),
                        );
                        if (result == true) {
                          final firebaseService = FirebaseService();
                          final latestLectures = await firebaseService
                              .getLectures(teacher.id);
                          setState(() {
                            _lectures[teacher.id] = latestLectures;
                          });
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(
                          bottom: 16,
                          left: 12,
                          right: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade300,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Hero(
                                    tag: 'teacher_avatar_${teacher.id}',
                                    child: CircleAvatar(
                                      backgroundColor: Colors.blue.shade100,
                                      radius: 26,
                                      child: Text(
                                        teacher.name.isNotEmpty
                                            ? teacher.name[0].toUpperCase()
                                            : '?',
                                        style: textTheme.titleLarge?.copyWith(
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                teacher.name,
                                                style: textTheme.titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                            ),
                                            if (teacher.subjects.isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade600,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  teacher.subjects.first,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (lectures.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            '${lectures.length} lecture${lectures.length == 1 ? '' : 's'}',
                                            style: textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: Colors.grey.shade600,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () =>
                                            _showAddOrEditTeacherDialog(
                                              teacher: teacher,
                                            ),
                                        icon: Icon(
                                          Icons.edit,
                                          color: Colors.blue.shade600,
                                        ),
                                        tooltip: 'Edit',
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            _deleteTeacher(context, teacher),
                                        icon: Icon(
                                          Icons.delete,
                                          color: Colors.red.shade600,
                                        ),
                                        tooltip: 'Delete',
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _showAddOrEditTeacherDialog(
                                              teacher: teacher,
                                            );
                                          } else if (value == 'delete') {
                                            _deleteTeacher(context, teacher);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text(
                                              'Edit',
                                              style: textTheme.bodyMedium,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                              'Delete',
                                              style: textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: colorScheme.error,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.currency_rupee,
                                        color: Colors.green.shade600,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Rate: ₹${teacher.perHourRate.toStringAsFixed(2)}/hr',
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.onSurface
                                              .withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (teacher.subjects.isNotEmpty)
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: -8,
                                      children: teacher.subjects
                                          .map(
                                            (s) => Chip(
                                              label: Text(
                                                s,
                                                style:
                                                    theme.chipTheme.labelStyle,
                                              ),
                                              backgroundColor: theme
                                                  .chipTheme
                                                  .backgroundColor,
                                              padding: theme.chipTheme.padding,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Total Salary: ₹${totalSalary.toStringAsFixed(2)}',
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _isSaving ? null : () => _showAddOrEditTeacherDialog(),
            child: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 28),
            tooltip: 'Add Teacher',
          ),
        );
      },
    );
  }

  Widget _buildShimmerLoader(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: ListView.builder(
        itemCount: 4,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        itemBuilder: (context, idx) => Card(
          child: ListTile(
            leading: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
            title: Container(
              height: 18,
              width: 80,
              color: colorScheme.surfaceVariant,
              margin: const EdgeInsets.symmetric(vertical: 6),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: 120,
                  color: colorScheme.surfaceVariant.withOpacity(0.7),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                ),
                Container(
                  height: 12,
                  width: 60,
                  color: colorScheme.surfaceVariant.withOpacity(0.7),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
