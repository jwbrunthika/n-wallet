import 'package:equatable/equatable.dart';

class StudentSessionDto extends Equatable {
  const StudentSessionDto({
    required this.id,
    required this.sessionDate,
    required this.startTime,
    required this.endTime,
    required this.courseCode,
    required this.moduleCode,
    required this.moduleName,
    required this.hallId,
    required this.hallName,
    required this.batch,
    required this.deliveryMode,
    required this.lecturerEmail,
    required this.notes,
    required this.attendanceOpenMinutesBefore,
    required this.attendanceCloseMinutesAfter,
  });

  final String id;
  final String sessionDate;
  final String startTime;
  final String endTime;
  final String courseCode;
  final String moduleCode;
  final String moduleName;
  final String hallId;
  final String hallName;
  final String batch;
  final String deliveryMode;
  final String lecturerEmail;
  final String notes;
  final int attendanceOpenMinutesBefore;
  final int attendanceCloseMinutesAfter;

  factory StudentSessionDto.fromJson(Map<String, dynamic> json) {
    return StudentSessionDto(
      id: json['id'] as String,
      sessionDate: json['sessionDate'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      moduleCode: json['moduleCode'] as String? ?? '',
      moduleName: json['moduleName'] as String? ?? '',
      hallId: json['hallId'] as String? ?? '',
      hallName: json['hallName'] as String? ?? '',
      batch: json['batch'] as String? ?? '',
      deliveryMode: json['deliveryMode'] as String? ?? 'BOTH',
      lecturerEmail: json['lecturerEmail'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      attendanceOpenMinutesBefore:
          (json['attendanceOpenMinutesBefore'] as num?)?.toInt() ?? 0,
      attendanceCloseMinutesAfter:
          (json['attendanceCloseMinutesAfter'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    id,
    sessionDate,
    startTime,
    endTime,
    courseCode,
    moduleCode,
    moduleName,
    hallId,
    hallName,
    batch,
    deliveryMode,
    lecturerEmail,
    notes,
    attendanceOpenMinutesBefore,
    attendanceCloseMinutesAfter,
  ];
}
