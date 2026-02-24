<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\CourseModule;
use App\Models\LectureHall;
use App\Models\LectureSession;
use App\Models\TimetableImport;
use App\Models\UniversityCourse;
use App\Services\AcademicProfileService;
use App\Services\AuditLogService;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use League\Csv\Reader;

class TimetableImportController extends ApiController
{
    public function __construct(
        private readonly AuditLogService $auditLogService,
        private readonly AcademicProfileService $academicProfileService,
    ) {
    }

    public function import(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $request->validate([
                'file' => ['required', 'file', 'mimes:csv,txt'],
            ]);

            $file = $request->file('file');
            $reader = Reader::createFromPath((string) $file->getRealPath(), 'r');
            $reader->setHeaderOffset(0);

            $records = $reader->getRecords();
            $errors = [];
            $inserted = 0;
            $rowNumber = 1;
            $courses = UniversityCourse::query()->where('enabled', true)->get();
            $coursesByCode = [];
            $coursesByName = [];

            foreach ($courses as $course) {
                $normalizedCode = strtoupper(trim((string) $course->courseCode));
                $normalizedName = $this->normalizeLookupValue((string) $course->courseName);

                if ($normalizedCode !== '') {
                    $coursesByCode[$normalizedCode] = $course;
                }
                if ($normalizedName !== '') {
                    $coursesByName[$normalizedName] = $course;
                }
            }

            foreach ($records as $record) {
                $rowNumber++;
                try {
                    $normalizedRecord = $this->normalizeRecord($record);
                    $sessionDate = $this->normalizeSessionDate((string) ($normalizedRecord['session_date'] ?? ''));
                    $startTime = $this->normalizeSessionTime((string) ($normalizedRecord['start_time'] ?? ''), 'start_time');
                    $endTime = $this->normalizeSessionTime((string) ($normalizedRecord['end_time'] ?? ''), 'end_time');
                    $courseName = trim((string) ($normalizedRecord['course_name'] ?? ''));
                    $courseCode = strtoupper(trim((string) ($normalizedRecord['course_code'] ?? '')));
                    $moduleCode = strtoupper(trim((string) ($normalizedRecord['module_code'] ?? '')));
                    $moduleName = trim((string) ($normalizedRecord['module_name'] ?? ''));
                    $hallName = trim((string) ($normalizedRecord['hall_name'] ?? ''));
                    $batch = trim((string) ($normalizedRecord['batch'] ?? ''));

                    if ($endTime <= $startTime) {
                        throw new \RuntimeException('end_time must be later than start_time');
                    }
                    if ($courseName === '' && $courseCode === '') {
                        throw new \RuntimeException('course_name is required (or provide legacy course_code)');
                    }
                    if ($moduleCode === '' || $moduleName === '' || $hallName === '' || $batch === '') {
                        throw new \RuntimeException('module_code, module_name, hall_name and batch are required');
                    }

                    $course = null;
                    if ($courseName !== '') {
                        $course = $coursesByName[$this->normalizeLookupValue($courseName)] ?? null;
                    }
                    if (! $course && $courseCode !== '') {
                        $course = $coursesByCode[$courseCode] ?? null;
                    }

                    if (! $course) {
                        $identifier = $courseName !== '' ? $courseName : $courseCode;
                        throw new \RuntimeException("Unknown or disabled course: {$identifier}");
                    }
                    $courseCode = strtoupper(trim((string) $course->courseCode));
                    $deliveryMode = $this->normalizeDeliveryMode(
                        (string) ($normalizedRecord['delivery_mode'] ?? ''),
                        strtoupper((string) ($course->deliveryMode ?? LectureSession::DELIVERY_MODE_BOTH))
                    );

                    if (! $this->academicProfileService->isDeliveryModeAllowedForCourse($course, $deliveryMode)) {
                        throw new \RuntimeException("delivery_mode {$deliveryMode} is not allowed for course {$courseCode}");
                    }

                    if (! $this->academicProfileService->isBatchAllowedForCourse($course, $batch)) {
                        throw new \RuntimeException("batch {$batch} is not configured for course {$courseCode}");
                    }

                    $courseModuleCodes = collect($course->moduleCodes ?? [])
                        ->map(fn (mixed $code): string => strtoupper(trim((string) $code)))
                        ->filter(fn (string $code): bool => $code !== '')
                        ->values()
                        ->all();

                    if ($courseModuleCodes !== []) {
                        $resolvedModuleCode = $this->resolveModuleCode($moduleCode, $courseModuleCodes);
                        if ($resolvedModuleCode === null) {
                            throw new \RuntimeException("module_code {$moduleCode} is not assigned to course {$courseCode}");
                        }
                        $moduleCode = $resolvedModuleCode;
                    }

                    $hall = LectureHall::query()->firstOrCreate(['name' => $hallName], ['name' => $hallName]);

                    $module = CourseModule::query()->firstOrCreate(
                        ['moduleCode' => $moduleCode],
                        [
                            'moduleCode' => $moduleCode,
                            'moduleName' => $moduleName,
                            'leaderAdminId' => null,
                        ]
                    );

                    LectureSession::query()->create([
                        'sessionDate' => $sessionDate,
                        'startTime' => $startTime,
                        'endTime' => $endTime,
                        'courseCode' => $courseCode,
                        'moduleCode' => $moduleCode,
                        'moduleName' => (string) ($module->moduleName ?? $moduleName),
                        'hallId' => (string) $hall->_id,
                        'attendanceOpenMinutesBefore' => $this->normalizeMinuteValue(
                            $normalizedRecord['attendance_open_minutes_before'] ?? null,
                            15,
                            'attendance_open_minutes_before'
                        ),
                        'attendanceCloseMinutesAfter' => $this->normalizeMinuteValue(
                            $normalizedRecord['attendance_close_minutes_after'] ?? null,
                            10,
                            'attendance_close_minutes_after'
                        ),
                        'batch' => $batch,
                        'deliveryMode' => $deliveryMode,
                        'lecturerEmail' => trim((string) ($normalizedRecord['lecturer_email'] ?? '')),
                        'notes' => trim((string) ($normalizedRecord['notes'] ?? '')),
                    ]);

                    $inserted++;
                } catch (\Throwable $exception) {
                    $errors[] = [
                        'row' => $rowNumber,
                        'message' => $exception->getMessage(),
                    ];
                }
            }

            $errorCount = count($errors);
            $status = $errorCount === 0 ? 'SUCCESS' : ($inserted > 0 ? 'PARTIAL' : 'FAILED');
            $import = TimetableImport::query()->create([
                'importId' => (string) Str::uuid(),
                'filename' => $file->getClientOriginalName(),
                'uploaderAdminId' => (string) $request->user()->_id,
                'rowCount' => $inserted + $errorCount,
                'status' => $status,
                'errors' => $errors,
            ]);

            $this->auditLogService->log(
                (string) $request->user()->_id,
                'timetable_import',
                'timetable_import',
                (string) $import->_id,
                'Timetable CSV imported'
            );

            return $this->success([
                'importId' => $import->importId,
                'status' => $status,
                'inserted' => $inserted,
                'errorCount' => $errorCount,
                'totalRows' => $inserted + $errorCount,
                'errors' => $errors,
            ]);
        });
    }

    /**
     * @param array<int|string, mixed> $record
     * @return array<string, mixed>
     */
    private function normalizeRecord(array $record): array
    {
        $normalized = [];
        foreach ($record as $key => $value) {
            if (! is_string($key)) {
                continue;
            }
            $normalized[$this->normalizeHeader($key)] = $value;
        }

        return $normalized;
    }

    private function normalizeHeader(string $header): string
    {
        $header = trim(str_replace("\xEF\xBB\xBF", '', $header));
        $header = strtolower($header);

        return str_replace([' ', '-'], '_', $header);
    }

    private function normalizeLookupValue(string $value): string
    {
        return strtolower(trim($value));
    }

    private function normalizeSessionDate(string $sessionDate): string
    {
        $sessionDate = trim($sessionDate);
        if ($sessionDate === '') {
            throw new \RuntimeException('session_date is required');
        }

        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $sessionDate) === 1) {
            return $sessionDate;
        }

        if (preg_match('/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/', $sessionDate, $matches) !== 1) {
            throw new \RuntimeException('Invalid session_date format. Use YYYY-MM-DD or M/D/YYYY');
        }

        $first = (int) ($matches[1] ?? 0);
        $second = (int) ($matches[2] ?? 0);
        $year = (int) ($matches[3] ?? 0);
        $month = $first;
        $day = $second;

        if (! checkdate($month, $day, $year) && checkdate($day, $month, $year)) {
            $month = $second;
            $day = $first;
        }

        if (! checkdate($month, $day, $year)) {
            throw new \RuntimeException('Invalid session_date value');
        }

        return sprintf('%04d-%02d-%02d', $year, $month, $day);
    }

    private function normalizeSessionTime(string $time, string $field): string
    {
        $time = strtoupper(trim($time));
        if ($time === '') {
            throw new \RuntimeException("{$field} is required");
        }

        if (preg_match('/^(\d{1,2}):(\d{2})$/', $time, $matches) === 1) {
            return $this->formatTime((int) ($matches[1] ?? 0), (int) ($matches[2] ?? 0), $field);
        }

        if (preg_match('/^(\d{1,2})$/', $time, $matches) === 1) {
            return $this->formatTime((int) ($matches[1] ?? 0), 0, $field);
        }

        if (preg_match('/^(\d{1,2})\.(\d{1,2})$/', $time, $matches) === 1) {
            $hour = (int) ($matches[1] ?? 0);
            $fraction = (string) ($matches[2] ?? '');
            $minute = strlen($fraction) === 1 ? ((int) $fraction * 10) : (int) $fraction;

            return $this->formatTime($hour, $minute, $field);
        }

        if (preg_match('/^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)$/', $time, $matches) === 1) {
            $hour = (int) ($matches[1] ?? 0);
            $minute = (int) ($matches[2] ?? 0);
            if ($hour < 1 || $hour > 12) {
                throw new \RuntimeException("Invalid {$field} value: {$time}");
            }

            if (($matches[3] ?? 'AM') === 'AM') {
                $hour = $hour % 12;
            } else {
                $hour = ($hour % 12) + 12;
            }

            return $this->formatTime($hour, $minute, $field);
        }

        throw new \RuntimeException("Invalid {$field} format. Use HH:MM or hour value");
    }

    private function formatTime(int $hour, int $minute, string $field): string
    {
        if ($hour < 0 || $hour > 23 || $minute < 0 || $minute > 59) {
            throw new \RuntimeException("Invalid {$field} value");
        }

        return sprintf('%02d:%02d', $hour, $minute);
    }

    private function normalizeDeliveryMode(string $deliveryMode, string $courseMode): string
    {
        $courseMode = strtoupper(trim($courseMode));
        if (! in_array($courseMode, LectureSession::DELIVERY_MODES, true)) {
            $courseMode = LectureSession::DELIVERY_MODE_BOTH;
        }

        $deliveryMode = strtoupper(trim($deliveryMode));
        if ($deliveryMode === '') {
            return $courseMode;
        }

        if (in_array($deliveryMode, LectureSession::DELIVERY_MODES, true)) {
            return $deliveryMode;
        }

        $canonical = str_replace([' ', '-'], '_', $deliveryMode);
        $canonicalMap = [
            'WEEKDAYS' => LectureSession::DELIVERY_MODE_WEEKDAY,
            'WEEKENDS' => LectureSession::DELIVERY_MODE_WEEKEND,
            'ALL' => LectureSession::DELIVERY_MODE_BOTH,
            'ANY' => LectureSession::DELIVERY_MODE_BOTH,
        ];
        if (isset($canonicalMap[$canonical])) {
            return $canonicalMap[$canonical];
        }

        $fallbackAliases = [
            'DIRECT',
            'IN_PERSON',
            'INPERSON',
            'FACE_TO_FACE',
            'FACE2FACE',
            'ONSITE',
            'ON_SITE',
            'ONCAMPUS',
            'ON_CAMPUS',
            'PHYSICAL',
            'ONLINE',
            'VIRTUAL',
            'REMOTE',
            'HYBRID',
        ];

        if (in_array($canonical, $fallbackAliases, true)) {
            return $courseMode;
        }

        throw new \RuntimeException("Invalid delivery_mode: {$deliveryMode}");
    }

    /**
     * @param array<int, string> $courseModuleCodes
     */
    private function resolveModuleCode(string $moduleCode, array $courseModuleCodes): ?string
    {
        if (in_array($moduleCode, $courseModuleCodes, true)) {
            return $moduleCode;
        }

        $target = $this->canonicalModuleCode($moduleCode);
        if ($target === '') {
            return null;
        }

        foreach ($courseModuleCodes as $courseModuleCode) {
            if ($this->canonicalModuleCode($courseModuleCode) === $target) {
                return $courseModuleCode;
            }
        }

        return null;
    }

    private function canonicalModuleCode(string $moduleCode): string
    {
        $moduleCode = strtoupper(trim($moduleCode));

        return preg_replace('/[^A-Z0-9]/', '', $moduleCode) ?? '';
    }

    private function normalizeMinuteValue(mixed $value, int $default, string $field): int
    {
        $value = trim((string) $value);
        if ($value === '') {
            return $default;
        }
        if (! is_numeric($value)) {
            throw new \RuntimeException("{$field} must be numeric");
        }

        $minutes = (int) round((float) $value);
        if ($minutes < 0 || $minutes > 180) {
            throw new \RuntimeException("{$field} must be between 0 and 180");
        }

        return $minutes;
    }
}
