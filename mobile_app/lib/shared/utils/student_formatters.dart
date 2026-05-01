import 'dart:math' as math;

String displayLecturer(String email) {
  if (email.isEmpty) return 'Lecturer';
  final local = email.split('@').first;
  final words = local
      .replaceAll(RegExp(r'[_\.-]+'), ' ')
      .split(' ')
      .where((word) => word.trim().isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .toList();
  return words.isEmpty ? email : words.join(' ');
}

String displayHall(String hallName, String hallId) {
  final trimmedName = hallName.trim();
  if (trimmedName.isNotEmpty) {
    return trimmedName;
  }

  if (hallId.trim().isEmpty) {
    return 'Lecture Hall';
  }
  return 'Lecture Hall $hallId';
}

String initialsFromEmail(String? email) {
  if (email == null || email.isEmpty) return 'NW';
  final local = email.split('@').first;
  final words = local
      .replaceAll(RegExp(r'[_\.-]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();

  if (words.isEmpty) return 'NW';
  if (words.length == 1) {
    return words.first
        .substring(0, math.min(2, words.first.length))
        .toUpperCase();
  }

  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

String nameFromEmail(String? email) {
  if (email == null || email.isEmpty) return 'Student';
  final local = email.split('@').first;
  final words = local
      .replaceAll(RegExp(r'[_\.-]+'), ' ')
      .split(' ')
      .where((word) => word.trim().isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .toList();

  return words.join(' ');
}

String maskEmail(String email) {
  final parts = email.split('@');
  if (parts.length != 2) return email;

  final local = parts[0];
  if (local.length <= 3) {
    return '${local[0]}***@${parts[1]}';
  }

  final visible = local.substring(0, 3);
  final hidden = List<String>.filled(local.length - 3, '*').join();
  return '$visible$hidden@${parts[1]}';
}

String formatCountdown(int totalSeconds) {
  final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final ss = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}
