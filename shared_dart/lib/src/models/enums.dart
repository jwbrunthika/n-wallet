enum EnrollmentStatus { notEnrolled, enrolled, failed }

enum Role { superAdmin, academicAdmin, moduleLeader, support }

EnrollmentStatus enrollmentStatusFromApi(String value) {
  switch (value) {
    case 'ENROLLED':
      return EnrollmentStatus.enrolled;
    case 'FAILED':
      return EnrollmentStatus.failed;
    default:
      return EnrollmentStatus.notEnrolled;
  }
}

Role roleFromApi(String value) {
  switch (value) {
    case 'ACADEMIC_ADMIN':
      return Role.academicAdmin;
    case 'MODULE_LEADER':
      return Role.moduleLeader;
    case 'SUPPORT':
      return Role.support;
    default:
      return Role.superAdmin;
  }
}
