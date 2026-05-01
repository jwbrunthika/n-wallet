import 'package:shared_dart/shared_dart.dart';

DateTime? buildSessionTime(String date, String time) {
  final dateParts = date.split('-');
  final timeParts = time.split(':');
  if (dateParts.length != 3 || timeParts.length < 2) return null;

  final year = int.tryParse(dateParts[0]);
  final month = int.tryParse(dateParts[1]);
  final day = int.tryParse(dateParts[2]);
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);

  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null) {
    return null;
  }

  return DateTime(year, month, day, hour, minute);
}

String formatTo12Hour(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;

  final hour24 = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour24 == null || minute == null) return hhmm;

  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = ((hour24 + 11) % 12) + 1;
  return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $suffix';
}

String formatDateTimeTo12Hour(DateTime value) {
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  final hour12 = ((value.hour + 11) % 12) + 1;
  return '${hour12.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} $suffix';
}

String formatHourMinute(String hhmm) {
  final parts = formatTo12Hour(hhmm).split(' ');
  return parts.first;
}

String formatAmPmShort(String hhmm) {
  final parts = formatTo12Hour(hhmm).split(' ');
  return parts.length > 1 ? parts.last : '';
}

String formatDateReadable(String ymd) {
  final parts = ymd.split('-');
  if (parts.length != 3) return ymd;

  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return ymd;

  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${months[month - 1]} $day, $year';
}

String attendanceWindowLabel(StudentSessionDto session) {
  final open = attendanceWindowOpensAt(session);
  final close = attendanceWindowClosesAt(session);
  if (open == null || close == null) {
    return 'Attendance window unavailable';
  }
  if (!close.isAfter(open)) {
    return 'Attendance window misconfigured';
  }

  return '${formatDateTimeTo12Hour(open)} - ${formatDateTimeTo12Hour(close)}';
}

DateTime? attendanceWindowOpensAt(StudentSessionDto session) {
  final start = buildSessionTime(session.sessionDate, session.startTime);
  if (start == null) return null;

  return start.add(Duration(minutes: session.attendanceOpenMinutesBefore));
}

DateTime? attendanceWindowClosesAt(StudentSessionDto session) {
  final end = buildSessionTime(session.sessionDate, session.endTime);
  if (end == null) return null;

  return end.subtract(Duration(minutes: session.attendanceCloseMinutesAfter));
}

String formatDateTimeFromIso(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '-';

  return '${formatDateReadable(dt.toIso8601String().split('T').first)} • ${formatTo12Hour('${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}')}';
}

String formatDateTimeShort(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '-';

  final date = formatDateReadable(dt.toIso8601String().split('T').first);
  final time = formatTo12Hour(
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
  );
  return '$date, $time';
}

String monthGroupLabel(String? iso) {
  final dt = DateTime.tryParse(iso ?? '');
  if (dt == null) return 'UNKNOWN';

  const months = <String>[
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  return '${months[dt.month - 1]} ${dt.year}';
}
