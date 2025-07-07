class Student {
  final Map<String, dynamic> data;
  final String id;

  Student({required this.data, required this.id});

  // Flexible name getter that tries multiple possible column names
  String get name {
    final possibleNames = [
      'student name',
      'name',
      'student',
      'full name',
      'student_name',
    ];
    for (String key in possibleNames) {
      if (data.containsKey(key) && data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    // Try to find any column containing 'name'
    for (String key in data.keys) {
      if (key.toLowerCase().contains('name') &&
          data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    return 'Unknown';
  }

  // Flexible school getter
  String get school {
    final possibleNames = [
      'school name',
      'school',
      'school_name',
      'institution',
    ];
    for (String key in possibleNames) {
      if (data.containsKey(key) && data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    // Try to find any column containing 'school'
    for (String key in data.keys) {
      if (key.toLowerCase().contains('school') &&
          data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    return '';
  }

  // Flexible division getter
  String get division {
    final possibleNames = ['division', 'class', 'grade', 'section'];
    for (String key in possibleNames) {
      if (data.containsKey(key) && data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    // Try to find any column containing 'division' or 'class'
    for (String key in data.keys) {
      if ((key.toLowerCase().contains('division') ||
              key.toLowerCase().contains('class')) &&
          data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    return '';
  }

  // Flexible standard getter
  String get standard {
    final possibleNames = ['standard', 'class', 'grade', 'year', 'level'];
    for (String key in possibleNames) {
      if (data.containsKey(key) && data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    // Try to find any column containing 'standard', 'class', or 'grade'
    for (String key in data.keys) {
      if ((key.toLowerCase().contains('standard') ||
              key.toLowerCase().contains('class') ||
              key.toLowerCase().contains('grade')) &&
          data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    return '';
  }

  // Flexible student number getter
  String get studentNumber {
    final possibleNames = [
      'student number',
      'student_number',
      'roll number',
      'roll_number',
      'roll no',
      'roll_no',
      'id',
      'student id',
      'student_id',
    ];
    for (String key in possibleNames) {
      if (data.containsKey(key) && data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    // Try to find any column containing 'number', 'roll', or 'id'
    for (String key in data.keys) {
      if ((key.toLowerCase().contains('number') ||
              key.toLowerCase().contains('roll') ||
              key.toLowerCase().contains('id')) &&
          data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    return '';
  }

  // Flexible fee getters
  String get totalFees {
    final possibleNames = [
      'total fees',
      'total_fees',
      'total',
      'fees',
      'amount',
      'total amount',
    ];
    for (String key in possibleNames) {
      if (data.containsKey(key) && data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    // Try to find any column containing 'total' and 'fee'
    for (String key in data.keys) {
      if (key.toLowerCase().contains('total') &&
          key.toLowerCase().contains('fee') &&
          data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    return '0';
  }

  String get paidFees {
    final possibleNames = [
      'paid fees',
      'paid_fees',
      'paid',
      'paid amount',
      'amount paid',
    ];
    for (String key in possibleNames) {
      if (data.containsKey(key) && data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    // Try to find any column containing 'paid'
    for (String key in data.keys) {
      if (key.toLowerCase().contains('paid') &&
          data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    return '0';
  }

  String get pendingFees {
    final possibleNames = [
      'pending fees',
      'pending_fees',
      'pending',
      'balance',
      'remaining',
      'due',
    ];
    for (String key in possibleNames) {
      if (data.containsKey(key) && data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }
    // Try to find any column containing 'pending' or 'balance'
    for (String key in data.keys) {
      if ((key.toLowerCase().contains('pending') ||
              key.toLowerCase().contains('balance') ||
              key.toLowerCase().contains('due')) &&
          data[key]?.toString().isNotEmpty == true) {
        return data[key].toString();
      }
    }

    // If no pending fees column exists, calculate it
    final total = totalFeesAmount;
    final paid = paidFeesAmount;
    final pending = total - paid;
    return pending.toString();
  }

  double get totalFeesAmount =>
      double.tryParse(totalFees.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
  double get paidFeesAmount =>
      double.tryParse(paidFees.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
  double get pendingFeesAmount =>
      double.tryParse(pendingFees.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;

  Map<String, dynamic> toMap() => data;

  Map<String, dynamic> toJson() {
    return {'id': id, 'data': data};
  }

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as String,
      data: Map<String, dynamic>.from(json['data']),
    );
  }

  factory Student.fromMap(Map<String, dynamic> data, String id) {
    return Student(data: data, id: id);
  }

  Student copyWith({Map<String, dynamic>? data, String? id}) {
    return Student(data: data ?? this.data, id: id ?? this.id);
  }
}
