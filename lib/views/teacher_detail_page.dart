import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/teacher.dart';
import '../services/firebase_service.dart';

class TeacherDetailPage extends StatefulWidget {
  final Teacher teacher;
  final List<Lecture> lectures;
  final Function(String teacherId, List<Lecture> lectures)? onLecturesUpdated;

  const TeacherDetailPage({
    Key? key,
    required this.teacher,
    required this.lectures,
    this.onLecturesUpdated,
  }) : super(key: key);

  @override
  State<TeacherDetailPage> createState() => _TeacherDetailPageState();
}

class _TeacherDetailPageState extends State<TeacherDetailPage> {
  late List<Lecture> _lectures;
  bool _isLoading = false;
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    _lectures = [];
    _fetchLectures();
  }

  Future<void> _fetchLectures() async {
    setState(() => _isLoading = true);
    final lectures = await _firebaseService.getLectures(widget.teacher.id);
    setState(() {
      _lectures = lectures;
      _isLoading = false;
    });
    widget.onLecturesUpdated?.call(widget.teacher.id, lectures);
  }

  void _showAddLectureDialog() {
    String? selectedSubject = widget.teacher.subjects.isNotEmpty
        ? widget.teacher.subjects.first
        : null;
    final hoursController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    final formKey = GlobalKey<FormState>();

    void updateHours() {
      if (startTime != null && endTime != null) {
        final start = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          startTime!.hour,
          startTime!.minute,
        );
        final end = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          endTime!.hour,
          endTime!.minute,
        );
        double diff = end.difference(start).inMinutes / 60.0;
        if (diff < 0) diff += 24; // handle overnight
        hoursController.text = diff.toStringAsFixed(2);
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Add Lecture for ${widget.teacher.name}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedSubject,
                  items: widget.teacher.subjects
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedSubject = val),
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: (val) =>
                      val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Date:'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null)
                          setState(() => selectedDate = picked);
                      },
                      child: Text(
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Start Time:'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime:
                              startTime ?? TimeOfDay(hour: 8, minute: 0),
                        );
                        if (picked != null)
                          setState(() {
                            startTime = picked;
                            updateHours();
                          });
                      },
                      child: Text(
                        startTime != null
                            ? startTime!.format(context)
                            : 'Select',
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('End Time:'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime:
                              endTime ?? TimeOfDay(hour: 10, minute: 0),
                        );
                        if (picked != null)
                          setState(() {
                            endTime = picked;
                            updateHours();
                          });
                      },
                      child: Text(
                        endTime != null ? endTime!.format(context) : 'Select',
                      ),
                    ),
                  ],
                ),
                if (startTime != null && endTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      'Time Period: ${startTime!.format(context)} - ${endTime!.format(context)}',
                    ),
                  ),
                TextFormField(
                  controller: hoursController,
                  decoration: const InputDecoration(labelText: 'Hours'),
                  keyboardType: TextInputType.number,
                  readOnly: true,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Required';
                    final d = double.tryParse(val);
                    if (d == null || d <= 0) return 'Enter valid hours';
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
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final hours =
                      double.tryParse(hoursController.text.trim()) ?? 0.0;
                  final amount = hours * widget.teacher.perHourRate;
                  final lecture = Lecture(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    teacherId: widget.teacher.id,
                    subject: selectedSubject!,
                    dateTime: selectedDate,
                    hours: hours,
                    amount: amount,
                    startTime: startTime,
                    endTime: endTime,
                  );
                  await _firebaseService.addLecture(widget.teacher.id, lecture);
                  setState(() => _lectures.add(lecture));
                  widget.onLecturesUpdated?.call(widget.teacher.id, _lectures);
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Add Lecture'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditLectureDialog(Lecture lecture) {
    String? selectedSubject = lecture.subject;
    final hoursController = TextEditingController();
    var dateTime = lecture.dateTime;
    var startTime = lecture.startTime;
    var endTime = lecture.endTime;
    final formKey = GlobalKey<FormState>();

    void updateHours() {
      if (startTime != null && endTime != null) {
        final start = DateTime(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          startTime!.hour,
          startTime!.minute,
        );
        final end = DateTime(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          endTime!.hour,
          endTime!.minute,
        );
        double diff = end.difference(start).inMinutes / 60.0;
        if (diff < 0) diff += 24; // handle overnight
        hoursController.text = diff.toStringAsFixed(2);
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit Lecture for ${widget.teacher.name}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedSubject,
                  items: widget.teacher.subjects
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedSubject = val),
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: (val) =>
                      val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Date:'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: dateTime,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => dateTime = picked);
                      },
                      child: Text(
                        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Start Time:'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime:
                              startTime ?? TimeOfDay(hour: 8, minute: 0),
                        );
                        if (picked != null)
                          setState(() {
                            startTime = picked;
                            updateHours();
                          });
                      },
                      child: Text(
                        startTime != null
                            ? startTime!.format(context)
                            : 'Select',
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('End Time:'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime:
                              endTime ?? TimeOfDay(hour: 10, minute: 0),
                        );
                        if (picked != null)
                          setState(() {
                            endTime = picked;
                            updateHours();
                          });
                      },
                      child: Text(
                        endTime != null ? endTime!.format(context) : 'Select',
                      ),
                    ),
                  ],
                ),
                if (startTime != null && endTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      'Time Period: ${startTime!.format(context)} - ${endTime!.format(context)}',
                    ),
                  ),
                TextFormField(
                  controller: hoursController,
                  decoration: const InputDecoration(labelText: 'Hours'),
                  keyboardType: TextInputType.number,
                  readOnly: true,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Required';
                    final d = double.tryParse(val);
                    if (d == null || d <= 0) return 'Enter valid hours';
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
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final hours =
                      double.tryParse(hoursController.text.trim()) ?? 0.0;
                  final amount = hours * widget.teacher.perHourRate;
                  final updatedLecture = Lecture(
                    id: lecture.id,
                    teacherId: widget.teacher.id,
                    subject: selectedSubject!,
                    dateTime: dateTime,
                    hours: hours,
                    amount: amount,
                    startTime: startTime,
                    endTime: endTime,
                  );
                  await _firebaseService.updateLecture(
                    widget.teacher.id,
                    updatedLecture,
                  );
                  setState(() => _lectures.remove(lecture));
                  setState(() => _lectures.add(updatedLecture));
                  widget.onLecturesUpdated?.call(widget.teacher.id, _lectures);
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Update Lecture'),
            ),
          ],
        ),
      ),
    );
  }

  double _teacherTotalSalary() {
    return _lectures.fold(0.0, (sum, l) => sum + l.amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Details'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  Navigator.of(context).pop('edit');
                  break;
                case 'delete':
                  Navigator.of(context).pop('delete');
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
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            widget.teacher.name.isNotEmpty
                                ? widget.teacher.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 32,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.teacher.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (widget.teacher.subjects.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Subjects: ${widget.teacher.subjects.join(', ')}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Personal Info Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personal Information',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow('Name', widget.teacher.name),
                          if (widget.teacher.subjects.isNotEmpty)
                            _buildInfoRow(
                              'Subjects',
                              widget.teacher.subjects.join(', '),
                            ),
                          _buildInfoRow(
                            'Rate',
                            '₹${widget.teacher.perHourRate.toStringAsFixed(2)}/hr',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Salary & Lectures Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Salary & Lectures',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow(
                            'Total Salary',
                            '₹${_teacherTotalSalary().toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Lectures',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _lectures.isEmpty
                              ? const Text('No lectures yet.')
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _lectures.length,
                                  separatorBuilder: (context, idx) =>
                                      const Divider(),
                                  itemBuilder: (context, idx) {
                                    final lecture = _lectures[idx];
                                    final date = lecture.dateTime;
                                    final dateStr =
                                        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                                    final start = lecture.startTime != null
                                        ? lecture.startTime!.format(context)
                                        : '';
                                    final end = lecture.endTime != null
                                        ? lecture.endTime!.format(context)
                                        : '';
                                    return ListTile(
                                      leading: const Icon(
                                        Icons.menu_book,
                                        color: Colors.blueAccent,
                                        size: 28,
                                      ),
                                      title: Text(
                                        lecture.subject,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Date: $dateStr',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (start.isNotEmpty &&
                                              end.isNotEmpty)
                                            Text(
                                              'Time: $start - $end',
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          Text(
                                            'Hours: ${lecture.hours}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '₹${lecture.amount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                              fontSize: 15,
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            onSelected: (value) async {
                                              if (value == 'edit') {
                                                _showEditLectureDialog(lecture);
                                              } else if (value == 'delete') {
                                                final confirmed = await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    title: const Text(
                                                      'Delete Lecture',
                                                    ),
                                                    content: const Text(
                                                      'Are you sure you want to delete this lecture?',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                              false,
                                                            ),
                                                        child: const Text(
                                                          'Cancel',
                                                        ),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                              true,
                                                            ),
                                                        child: const Text(
                                                          'Delete',
                                                        ),
                                                        style:
                                                            ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors.red,
                                                              foregroundColor:
                                                                  Colors.white,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirmed == true) {
                                                  await _firebaseService
                                                      .deleteLecture(
                                                        widget.teacher.id,
                                                        lecture.id,
                                                      );
                                                  setState(
                                                    () =>
                                                        _lectures.removeAt(idx),
                                                  );
                                                  widget.onLecturesUpdated
                                                      ?.call(
                                                        widget.teacher.id,
                                                        _lectures,
                                                      );
                                                }
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
                                                    Icon(
                                                      Icons.delete,
                                                      color: Colors.red,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Delete',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Add Lecture Button
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _showAddLectureDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Lecture'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
