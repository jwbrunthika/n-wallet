<?php

namespace App\Services;

use App\Models\AttendanceRecord;
use App\Models\CourseModule;
use App\Models\LectureSession;
use App\Models\Student;
use App\Models\UniversityCourse;
use App\Support\ApiException;
use Carbon\Carbon;
use Illuminate\Support\Collection;

class AttendanceReportService
{
    public function __construct(private readonly AcademicProfileService $academicProfileService)
    {
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function studentReport(array $payload): array
    {
        $period = $this->resolvePeriod($payload);
        $studentEmail = strtolower(trim((string) ($payload['studentEmail'] ?? '')));
        $student = Student::query()->where('email', $studentEmail)->first();

        if (! $student) {
            throw new ApiException('STUDENT_NOT_FOUND', 'Student not found.', 404);
        }

        $profileComplete = $this->academicProfileService->hasAcademicProfile($student);
        $course = $profileComplete
            ? UniversityCourse::query()->where('courseCode', strtoupper((string) $student->courseCode))->first()
            : null;

        $moduleCodes = collect($course?->moduleCodes ?? [])
            ->map(fn (mixed $value): string => strtoupper(trim((string) $value)))
            ->filter(fn (string $value): bool => $value !== '')
            ->unique()
            ->values();

        $modulesByCode = CourseModule::query()
            ->whereIn('moduleCode', $moduleCodes->all())
            ->get()
            ->keyBy(fn (CourseModule $module): string => strtoupper((string) $module->moduleCode));

        $moduleRows = [];
        foreach ($moduleCodes as $moduleCode) {
            $module = $modulesByCode->get($moduleCode);
            $moduleRows[$moduleCode] = [
                'moduleCode' => $moduleCode,
                'moduleName' => (string) ($module?->moduleName ?? "Module {$moduleCode}"),
                'scheduled' => 0,
                'attended' => 0,
                'failed' => 0,
            ];
        }

        $sessions = collect();
        if ($profileComplete) {
            $sessions = LectureSession::query()
                ->where('courseCode', strtoupper((string) $student->courseCode))
                ->orderBy('sessionDate')
                ->orderBy('startTime')
                ->get()
                ->filter(fn (LectureSession $session): bool => $this->isSessionInPeriod($session, $period))
                ->filter(fn (LectureSession $session): bool => $this->academicProfileService->isSessionAssignedToStudent($student, $session))
                ->values();
        }

        $recordsBySession = $this->attendanceRecordsForStudent($studentEmail, $sessions);
        $sessionRows = [];
        $totals = ['scheduled' => 0, 'attended' => 0, 'failed' => 0];

        foreach ($sessions as $session) {
            $sessionId = (string) $session->_id;
            $moduleCode = strtoupper((string) $session->moduleCode);
            if (! isset($moduleRows[$moduleCode])) {
                $moduleRows[$moduleCode] = [
                    'moduleCode' => $moduleCode,
                    'moduleName' => (string) ($session->moduleName ?: "Module {$moduleCode}"),
                    'scheduled' => 0,
                    'attended' => 0,
                    'failed' => 0,
                ];
            }

            /** @var AttendanceRecord|null $record */
            $record = $recordsBySession->get($sessionId);
            $attended = $record?->status === AttendanceRecord::STATUS_PRESENT;
            $failed = ! $attended;

            $moduleRows[$moduleCode]['scheduled']++;
            $moduleRows[$moduleCode][$attended ? 'attended' : 'failed']++;
            $totals['scheduled']++;
            $totals[$attended ? 'attended' : 'failed']++;

            $sessionRows[] = [
                'sessionId' => $sessionId,
                'sessionDate' => $session->sessionDate,
                'startTime' => $session->startTime,
                'endTime' => $session->endTime,
                'courseCode' => $session->courseCode,
                'moduleCode' => $moduleCode,
                'moduleName' => $session->moduleName,
                'hallId' => $session->hallId,
                'batch' => $session->batch,
                'deliveryMode' => $session->deliveryMode,
                'recordStatus' => $record?->status ?? 'ABSENT',
                'attendanceStatus' => $attended ? AttendanceRecord::STATUS_PRESENT : 'FAILED',
                'reasonCode' => $record?->reasonCode,
                'faceScore' => $record ? (float) $record->faceScore : null,
            ];
        }

        return [
            'reportType' => 'student',
            'period' => $period,
            'student' => [
                'email' => $student->email,
                'name' => $student->name,
                'enrollmentStatus' => $student->enrollmentStatus,
                'courseCode' => $student->courseCode,
                'batch' => $student->batch,
                'studyMode' => $student->studyMode,
                'profileComplete' => $profileComplete,
            ],
            'course' => $course ? [
                'courseCode' => $course->courseCode,
                'courseName' => $course->courseName,
                'deliveryMode' => $course->deliveryMode,
                'batchCount' => (int) ($course->batchCount ?? 0),
                'batchLabels' => array_values($course->batchLabels ?? []),
            ] : null,
            'modules' => array_values($moduleRows),
            'totals' => $totals,
            'sessions' => $sessionRows,
        ];
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function moduleReport(array $payload): array
    {
        $period = $this->resolvePeriod($payload);
        $moduleCode = strtoupper(trim((string) ($payload['moduleCode'] ?? '')));
        $module = CourseModule::query()->where('moduleCode', $moduleCode)->first();

        if (! $module) {
            throw new ApiException('MODULE_NOT_FOUND', 'Module not found.', 404);
        }

        $sessions = LectureSession::query()
            ->where('moduleCode', $moduleCode)
            ->orderBy('sessionDate')
            ->orderBy('startTime')
            ->get()
            ->filter(fn (LectureSession $session): bool => $this->isSessionInPeriod($session, $period))
            ->values();

        $recordsBySessionStudent = $this->attendanceRecordsForSessions($sessions);
        $students = Student::query()
            ->get()
            ->filter(fn (Student $student): bool => $this->academicProfileService->hasAcademicProfile($student))
            ->values();

        $daily = [];
        $sessionRows = [];
        $uniqueEnrolledStudents = [];
        $totals = ['expected' => 0, 'attended' => 0, 'failed' => 0];

        foreach ($sessions as $session) {
            $sessionId = (string) $session->_id;
            $date = (string) $session->sessionDate;
            $daily[$date] ??= [
                'date' => $date,
                'expected' => 0,
                'attended' => 0,
                'failed' => 0,
            ];

            $expectedStudents = $students
                ->filter(fn (Student $student): bool => $this->academicProfileService->isSessionAssignedToStudent($student, $session))
                ->values();

            $expected = $expectedStudents->count();
            $attended = 0;

            foreach ($expectedStudents as $student) {
                $studentEmail = (string) $student->email;
                $uniqueEnrolledStudents[$studentEmail] = true;
                $record = $recordsBySessionStudent[$sessionId][$studentEmail] ?? null;
                if ($record?->status === AttendanceRecord::STATUS_PRESENT) {
                    $attended++;
                }
            }

            $failed = max(0, $expected - $attended);

            $daily[$date]['expected'] += $expected;
            $daily[$date]['attended'] += $attended;
            $daily[$date]['failed'] += $failed;
            $totals['expected'] += $expected;
            $totals['attended'] += $attended;
            $totals['failed'] += $failed;

            $sessionRows[] = [
                'sessionId' => $sessionId,
                'sessionDate' => $date,
                'startTime' => $session->startTime,
                'endTime' => $session->endTime,
                'courseCode' => $session->courseCode,
                'moduleCode' => $session->moduleCode,
                'moduleName' => $session->moduleName,
                'hallId' => $session->hallId,
                'batch' => $session->batch,
                'deliveryMode' => $session->deliveryMode,
                'expected' => $expected,
                'attended' => $attended,
                'failed' => $failed,
            ];
        }

        ksort($daily);

        return [
            'reportType' => 'module',
            'period' => $period,
            'module' => [
                'moduleCode' => $moduleCode,
                'moduleName' => $module->moduleName,
                'leaderAdminId' => $module->leaderAdminId,
            ],
            'enrolledStudentCount' => count($uniqueEnrolledStudents),
            'totals' => $totals,
            'daily' => array_values($daily),
            'sessions' => $sessionRows,
        ];
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    private function resolvePeriod(array $payload): array
    {
        $now = now();
        $type = strtolower((string) ($payload['periodType'] ?? 'day'));
        $year = (int) ($payload['year'] ?? $now->year);
        $month = (int) ($payload['month'] ?? $now->month);
        $day = (int) ($payload['day'] ?? $now->day);

        if ($type === 'month') {
            if (! checkdate($month, 1, $year)) {
                throw new ApiException('INVALID_REPORT_PERIOD', 'Invalid report month.', 422);
            }

            $from = Carbon::create($year, $month, 1)->startOfDay();
            $to = $from->copy()->endOfMonth();

            return [
                'type' => 'month',
                'year' => $year,
                'month' => $month,
                'day' => null,
                'from' => $from->format('Y-m-d'),
                'to' => $to->format('Y-m-d'),
                'label' => $from->format('F Y'),
            ];
        }

        if (! checkdate($month, $day, $year)) {
            throw new ApiException('INVALID_REPORT_PERIOD', 'Invalid report date.', 422);
        }

        $date = Carbon::create($year, $month, $day)->startOfDay();

        return [
            'type' => 'day',
            'year' => $year,
            'month' => $month,
            'day' => $day,
            'from' => $date->format('Y-m-d'),
            'to' => $date->format('Y-m-d'),
            'label' => $date->format('Y-m-d'),
        ];
    }

    /**
     * @param array<string, mixed> $period
     */
    private function isSessionInPeriod(LectureSession $session, array $period): bool
    {
        $sessionDate = (string) $session->sessionDate;

        return $sessionDate >= (string) $period['from'] && $sessionDate <= (string) $period['to'];
    }

    /**
     * @param Collection<int, LectureSession> $sessions
     * @return Collection<string, AttendanceRecord>
     */
    private function attendanceRecordsForStudent(string $studentEmail, Collection $sessions): Collection
    {
        $sessionIds = $sessions
            ->map(fn (LectureSession $session): string => (string) $session->_id)
            ->values()
            ->all();

        if ($sessionIds === []) {
            return collect();
        }

        return AttendanceRecord::query()
            ->where('studentEmail', $studentEmail)
            ->whereIn('sessionId', $sessionIds)
            ->get()
            ->keyBy(fn (AttendanceRecord $record): string => (string) $record->sessionId);
    }

    /**
     * @param Collection<int, LectureSession> $sessions
     * @return array<string, array<string, AttendanceRecord>>
     */
    private function attendanceRecordsForSessions(Collection $sessions): array
    {
        $sessionIds = $sessions
            ->map(fn (LectureSession $session): string => (string) $session->_id)
            ->values()
            ->all();

        if ($sessionIds === []) {
            return [];
        }

        $records = [];
        foreach (AttendanceRecord::query()->whereIn('sessionId', $sessionIds)->get() as $record) {
            $sessionId = (string) $record->sessionId;
            $studentEmail = (string) $record->studentEmail;
            $records[$sessionId][$studentEmail] = $record;
        }

        return $records;
    }
}
