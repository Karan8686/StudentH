import 'package:flutter/material.dart';

class Teacher {
  final String id;
  final String name;
  final List<String> subjects;
  final double perHourRate;

  Teacher({
    required this.id,
    required this.name,
    required this.subjects,
    required this.perHourRate,
  });

  factory Teacher.fromMap(Map<String, dynamic> map, String id) {
    return Teacher(
      id: id,
      name: map['name'] ?? '',
      subjects: List<String>.from(map['subjects'] ?? []),
      perHourRate: (map['perHourRate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {'name': name, 'subjects': subjects, 'perHourRate': perHourRate};
  }
}

class Lecture {
  final String id;
  final String teacherId;
  final String subject;
  final DateTime dateTime;
  final double hours;
  final double amount;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;

  Lecture({
    required this.id,
    required this.teacherId,
    required this.subject,
    required this.dateTime,
    required this.hours,
    required this.amount,
    this.startTime,
    this.endTime,
  });

  factory Lecture.fromMap(
    Map<String, dynamic> map,
    String id,
    String teacherId,
  ) {
    TimeOfDay? parseTime(String? t) {
      if (t == null) return null;
      final parts = t.split(":");
      if (parts.length != 2) return null;
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return Lecture(
      id: id,
      teacherId: teacherId,
      subject: map['subject'] ?? '',
      dateTime: DateTime.parse(
        map['dateTime'] ?? DateTime.now().toIso8601String(),
      ),
      hours: (map['hours'] as num?)?.toDouble() ?? 0.0,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      startTime: parseTime(map['startTime'] as String?),
      endTime: parseTime(map['endTime'] as String?),
    );
  }

  Map<String, dynamic> toMap() {
    String? timeToString(TimeOfDay? t) =>
        t == null ? null : '${t.hour}:${t.minute}';
    return {
      'subject': subject,
      'dateTime': dateTime.toIso8601String(),
      'hours': hours,
      'amount': amount,
      'startTime': timeToString(startTime),
      'endTime': timeToString(endTime),
    };
  }
}
