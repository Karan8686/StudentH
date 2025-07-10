import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../viewmodels/teacher_viewmodel.dart';
import 'teacher_detail_page.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';
import 'package:flutter/rendering.dart';
import '../services/network_service.dart';
import 'no_network_screen.dart';

class TeachersPage extends StatefulWidget {
  const TeachersPage({Key? key}) : super(key: key);
  @override
  State<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends State<TeachersPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final Map<String, List<Lecture>> _lectures = {};
  bool _isSaving = false;
  late AnimationController _animationController;
  late AnimationController _fadeSlideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  final NetworkService _networkService = NetworkService();
  bool _isNetworkConnected = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeSlideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.2, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _fadeSlideController,
            curve: Curves.easeOutCubic,
          ),
        );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeSlideController,
      curve: Curves.easeIn,
    );
    _checkNetworkStatus();
    _loadTeachersAndLectures();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fadeSlideController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _checkNetworkStatus() async {
    final isConnected = await _networkService.checkConnection();
    if (mounted) {
      setState(() {
        _isNetworkConnected = isConnected;
      });
    }
  }

  Future<void> _loadTeachersAndLectures() async {
    if (!_isNetworkConnected) {
      return;
    }
    final viewModel = Provider.of<TeacherViewModel>(context, listen: false);
    try {
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
      _animationController.forward();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
    }
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isEdit ? Icons.edit : Icons.person_add,
                  color: Colors.blue.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isEdit ? 'Edit Teacher' : 'Add Teacher',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: subjectsController,
                  decoration: InputDecoration(
                    labelText: 'Subjects (space separated)',
                    prefixIcon: const Icon(Icons.school_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: rateController,
                  decoration: InputDecoration(
                    labelText: 'Per Hour Rate (₹)',
                    prefixIcon: const Icon(Icons.currency_rupee),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Teacher'),
        content: Text('Are you sure you want to delete ${teacher.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Teacher deleted successfully'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      } catch (e) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting teacher: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  double _teacherTotalSalary(String teacherId) {
    final lectures = _lectures[teacherId] ?? [];
    return lectures.fold(0.0, (sum, l) => sum + l.amount);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isNetworkConnected) {
      return NoNetworkScreen(onRetry: _checkNetworkStatus);
    }
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Consumer<TeacherViewModel>(
      builder: (context, viewModel, child) {
        final teachers = viewModel.teachers;
        if (!viewModel.isLoading) {
          _fadeSlideController.forward();
        } else {
          _fadeSlideController.reset();
        }
        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            title: Text(
              'Teachers',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (viewModel.error != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          viewModel.error!,
                          style: textTheme.bodyMedium?.copyWith(
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!viewModel.isLoading && teachers.isNotEmpty)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.group_outlined,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Teachers (${teachers.length})',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: viewModel.isLoading
                      ? _buildShimmerLoader(
                          theme,
                          viewModel.teachers.isNotEmpty
                              ? viewModel.teachers.length
                              : 2,
                        )
                      : teachers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.school_outlined,
                                size: 80,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No teachers yet',
                                style: textTheme.headlineSmall?.copyWith(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add your first teacher to get started',
                                style: textTheme.bodyLarge?.copyWith(
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: teachers.length,
                              padding: const EdgeInsets.only(
                                bottom: 80,
                                left: 16,
                                right: 16,
                              ),
                              itemBuilder: (context, idx) {
                                final teacher = teachers[idx];
                                return _buildTeacherCard(
                                  teacher,
                                  idx,
                                  theme,
                                  colorScheme,
                                  textTheme,
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _isSaving ? null : () => _showAddOrEditTeacherDialog(),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildTeacherCard(
    Teacher teacher,
    int index,
    ThemeData theme,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final totalSalary = _teacherTotalSalary(teacher.id);
    final lectures = _lectures[teacher.id] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TeacherDetailPage(
                teacher: teacher,
                lectures: List<Lecture>.from(_lectures[teacher.id] ?? []),
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
            final latestLectures = await firebaseService.getLectures(
              teacher.id,
            );
            setState(() {
              _lectures[teacher.id] = latestLectures;
            });
          }
        },
        borderRadius: BorderRadius.circular(12),
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
                      backgroundColor: Colors.blue.shade700,
                      radius: 24,
                      child: Text(
                        teacher.name.isNotEmpty
                            ? teacher.name[0].toUpperCase()
                            : '?',
                        style: textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          teacher.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (lectures.isNotEmpty)
                          Text(
                            '${lectures.length} lecture${lectures.length == 1 ? '' : 's'}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (teacher.subjects.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        teacher.subjects.first,
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showAddOrEditTeacherDialog(teacher: teacher);
                      } else if (value == 'delete') {
                        _deleteTeacher(context, teacher);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(color: Colors.red.shade600),
                            ),
                          ],
                        ),
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
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Rate: ₹${teacher.perHourRate.toStringAsFixed(2)}/hr',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (teacher.subjects.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: teacher.subjects
                          .map(
                            (s) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                s,
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Colors.blue.shade700,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Total Salary: ₹${totalSalary.toStringAsFixed(2)}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerLoader(ThemeData theme, int count) {
    return ListView.builder(
      itemCount: count,
      padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      itemBuilder: (context, idx) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 18,
                          width: 100,
                          color: Colors.grey.shade200,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          width: 60,
                          color: Colors.grey.shade200,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 24,
                    width: 48,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
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
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        height: 14,
                        width: 100,
                        color: Colors.grey.shade200,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: List.generate(
                      2,
                      (i) => Container(
                        height: 18,
                        width: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        height: 14,
                        width: 120,
                        color: Colors.grey.shade200,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
