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

class TimetableImportRowException extends \RuntimeException
{
    public function __construct(
        public readonly string $column,
        string $message,
        public readonly ?string $value = null,
    ) {
        parent::__construct($message);
    }
}

class TimetableImportController extends ApiController
{
    private const REQUIRED_HEADERS = [
        'session_date',
        'start_time',
        'end_time',
        'course_name',
        'module_code',
        'module_name',
        'hall_name',
        'batch',
        'delivery_mode',
        'lecturer_email',
        'attendance_open_minutes_after_start',
        'attendance_close_minutes_before_end',
        'notes',
    ];

    private const HEADER_ALIASES = [
        'attendance_open_minutes_before' => 'attendance_open_minutes_after_start',
        'attendance_close_minutes_after' => 'attendance_close_minutes_before_end',
    ];

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
            $errors = $this->validateHeaders($reader);
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

            if ($errors === []) {
                foreach ($records as $record) {
                    $rowNumber++;
                    try {
                        $rowErrors = [];
                        $normalizedRecord = $this->normalizeRecord($record);
                        $sessionDate = $this->captureField(
                            fn (): string => $this->normalizeSessionDate((string) ($normalizedRecord['session_date'] ?? ''), 'session_date'),
                            $rowErrors
                        );
                        $startTime = $this->captureField(
                            fn (): string => $this->normalizeSessionTime((string) ($normalizedRecord['start_time'] ?? ''), 'start_time'),
                            $rowErrors
                        );
                        $endTime = $this->captureField(
                            fn (): string => $this->normalizeSessionTime((string) ($normalizedRecord['end_time'] ?? ''), 'end_time'),
                            $rowErrors
                        );
                        $courseName = trim((string) ($normalizedRecord['course_name'] ?? ''));
                        $courseCode = strtoupper(trim((string) ($normalizedRecord['course_code'] ?? '')));
                        $moduleCode = strtoupper(trim((string) ($normalizedRecord['module_code'] ?? '')));
                        $moduleName = trim((string) ($normalizedRecord['module_name'] ?? ''));
                        $hallName = trim((string) ($normalizedRecord['hall_name'] ?? ''));
                        $batch = trim((string) ($normalizedRecord['batch'] ?? ''));

                        if ($startTime !== null && $endTime !== null && $endTime <= $startTime) {
                            $this->addRowError(
                                $rowErrors,
                                'end_time',
                                'end_time must be later than start_time',
                                $normalizedRecord['end_time'] ?? null
                            );
                        }
                        if ($courseName === '' && $courseCode === '') {
                            $this->addRowError(
                                $rowErrors,
                                'course_name',
                                'course_name is required (or provide legacy course_code)'
                            );
                        }
                        if ($moduleCode === '') {
                            $this->addRowError($rowErrors, 'module_code', 'module_code is required');
                        }
                        if ($moduleName === '') {
                            $this->addRowError($rowErrors, 'module_name', 'module_name is required');
                        }
                        if ($hallName === '') {
                            $this->addRowError($rowErrors, 'hall_name', 'hall_name is required');
                        }
                        if ($batch === '') {
                            $this->addRowError($rowErrors, 'batch', 'batch is required');
                        }

                        $course = null;
                        if ($courseName !== '' || $courseCode !== '') {
                            if ($courseName !== '') {
                                $course = $coursesByName[$this->normalizeLookupValue($courseName)] ?? null;
                            }
                            if (! $course && $courseCode !== '') {
                                $course = $coursesByCode[$courseCode] ?? null;
                            }

                            if (! $course) {
                                $identifier = $courseName !== '' ? $courseName : $courseCode;
                                $this->addRowError(
                                    $rowErrors,
                                    $courseName !== '' ? 'course_name' : 'course_code',
                                    "Unknown or disabled course: {$identifier}",
                                    $identifier
                                );
                            }
                        }
                        $deliveryMode = $course === null
                            ? null
                            : $this->captureField(
                                fn (): string => $this->normalizeDeliveryMode(
                                    (string) ($normalizedRecord['delivery_mode'] ?? ''),
                                    strtoupper((string) ($course->deliveryMode ?? LectureSession::DELIVERY_MODE_BOTH)),
                                    'delivery_mode'
                                ),
                                $rowErrors
                            );

                        if ($course !== null) {
                            $courseCode = strtoupper(trim((string) $course->courseCode));

                            if (
                                $deliveryMode !== null &&
                                ! $this->academicProfileService->isDeliveryModeAllowedForCourse($course, $deliveryMode)
                            ) {
                                $this->addRowError(
                                    $rowErrors,
                                    'delivery_mode',
                                    "delivery_mode {$deliveryMode} is not allowed for course {$courseCode}",
                                    $normalizedRecord['delivery_mode'] ?? null
                                );
                            }

                            if (
                                $batch !== '' &&
                                ! $this->academicProfileService->isBatchAllowedForCourse($course, $batch)
                            ) {
                                $this->addRowError(
                                    $rowErrors,
                                    'batch',
                                    "batch {$batch} is not configured for course {$courseCode}",
                                    $batch
                                );
                            }

                            $courseModuleCodes = collect($course->moduleCodes ?? [])
                                ->map(fn (mixed $code): string => strtoupper(trim((string) $code)))
                                ->filter(fn (string $code): bool => $code !== '')
                                ->values()
                                ->all();

                            if ($moduleCode !== '' && $courseModuleCodes !== []) {
                                $resolvedModuleCode = $this->resolveModuleCode($moduleCode, $courseModuleCodes);
                                if ($resolvedModuleCode === null) {
                                    $this->addRowError(
                                        $rowErrors,
                                        'module_code',
                                        "module_code {$moduleCode} is not assigned to course {$courseCode}",
                                        $moduleCode
                                    );
                                } else {
                                    $moduleCode = $resolvedModuleCode;
                                }
                            }
                        }

                        $attendanceOpenMinutesBefore = $this->captureField(
                            fn (): int => $this->normalizeMinuteValue(
                                $normalizedRecord['attendance_open_minutes_after_start'] ?? null,
                                15,
                                'attendance_open_minutes_after_start'
                            ),
                            $rowErrors
                        );
                        $attendanceCloseMinutesAfter = $this->captureField(
                            fn (): int => $this->normalizeMinuteValue(
                                $normalizedRecord['attendance_close_minutes_before_end'] ?? null,
                                10,
                                'attendance_close_minutes_before_end'
                            ),
                            $rowErrors
                        );

                        if ($rowErrors !== []) {
                            $this->appendRowErrors($errors, $rowNumber, $rowErrors);

                            continue;
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
                            'attendanceOpenMinutesBefore' => $attendanceOpenMinutesBefore,
                            'attendanceCloseMinutesAfter' => $attendanceCloseMinutesAfter,
                            'batch' => $batch,
                            'deliveryMode' => $deliveryMode,
                            'lecturerEmail' => trim((string) ($normalizedRecord['lecturer_email'] ?? '')),
                            'notes' => trim((string) ($normalizedRecord['notes'] ?? '')),
                        ]);

                        $inserted++;
                    } catch (\Throwable $exception) {
                        $errors[] = [
                            'row' => $rowNumber,
                            'column' => null,
                            'value' => null,
                            'message' => $exception->getMessage(),
                        ];
                    }
                }
            }

            $errorCount = count($errors);
            $errorRowCount = count(array_unique(array_map(
                fn (array $error): int => (int) ($error['row'] ?? 0),
                $errors
            )));
            $totalRows = $inserted + $errorRowCount;
            $status = $errorCount === 0 ? 'SUCCESS' : ($inserted > 0 ? 'PARTIAL' : 'FAILED');
            $import = TimetableImport::query()->create([
                'importId' => (string) Str::uuid(),
                'filename' => $file->getClientOriginalName(),
                'uploaderAdminId' => (string) $request->user()->_id,
                'rowCount' => $totalRows,
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
                'errorRowCount' => $errorRowCount,
                'totalRows' => $totalRows,
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
        $normalized = str_replace([' ', '-'], '_', $header);

        return self::HEADER_ALIASES[$normalized] ?? $normalized;
    }

    private function normalizeLookupValue(string $value): string
    {
        return strtolower(trim($value));
    }

    private function normalizeSessionDate(string $sessionDate, string $field): string
    {
        $sessionDate = trim($sessionDate);
        if ($sessionDate === '') {
            $this->invalidField($field, "{$field} is required");
        }

        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $sessionDate) === 1) {
            return $sessionDate;
        }

        if (preg_match('/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/', $sessionDate, $matches) !== 1) {
            $this->invalidField($field, 'Invalid session_date format. Use YYYY-MM-DD or M/D/YYYY', $sessionDate);
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
            $this->invalidField($field, 'Invalid session_date value', $sessionDate);
        }

        return sprintf('%04d-%02d-%02d', $year, $month, $day);
    }

    private function normalizeSessionTime(string $time, string $field): string
    {
        $time = strtoupper(trim($time));
        if ($time === '') {
            $this->invalidField($field, "{$field} is required");
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
                $this->invalidField($field, "Invalid {$field} value", $time);
            }

            if (($matches[3] ?? 'AM') === 'AM') {
                $hour = $hour % 12;
            } else {
                $hour = ($hour % 12) + 12;
            }

            return $this->formatTime($hour, $minute, $field);
        }

        $this->invalidField($field, "Invalid {$field} format. Use HH:MM or hour value", $time);
    }

    private function formatTime(int $hour, int $minute, string $field): string
    {
        if ($hour < 0 || $hour > 23 || $minute < 0 || $minute > 59) {
            $this->invalidField($field, "Invalid {$field} value", sprintf('%02d:%02d', $hour, $minute));
        }

        return sprintf('%02d:%02d', $hour, $minute);
    }

    private function normalizeDeliveryMode(string $deliveryMode, string $courseMode, string $field): string
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

        $this->invalidField($field, "Invalid {$field}: {$deliveryMode}", $deliveryMode);
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
            $this->invalidField($field, "{$field} must be numeric", $value);
        }

        $minutes = (int) round((float) $value);
        if ($minutes < 0 || $minutes > 180) {
            $this->invalidField($field, "{$field} must be between 0 and 180", (string) $minutes);
        }

        return $minutes;
    }

    /**
     * @return array<int, array{row:int, column:?string, value:?string, message:string}>
     */
    private function validateHeaders(Reader $reader): array
    {
        $normalizedHeaders = array_map(
            fn (mixed $header): string => $this->normalizeHeader((string) $header),
            $reader->getHeader()
        );

        $errors = [];
        foreach (self::REQUIRED_HEADERS as $header) {
            if (! in_array($header, $normalizedHeaders, true)) {
                $errors[] = [
                    'row' => 1,
                    'column' => $header,
                    'value' => null,
                    'message' => "Missing required header: {$header}",
                ];
            }
        }

        $headerCounts = array_count_values(array_filter($normalizedHeaders, fn (string $header): bool => $header !== ''));
        foreach ($headerCounts as $header => $count) {
            if ($count > 1) {
                $errors[] = [
                    'row' => 1,
                    'column' => $header,
                    'value' => $header,
                    'message' => "Duplicate header: {$header}",
                ];
            }
        }

        return $errors;
    }

    private function invalidField(string $column, string $message, mixed $value = null): never
    {
        throw new TimetableImportRowException($column, $message, $this->normalizeErrorValue($value));
    }

    /**
     * @param array<int, array{column:?string, value:?string, message:string}> $rowErrors
     */
    private function addRowError(array &$rowErrors, string $column, string $message, mixed $value = null): void
    {
        $rowErrors[] = [
            'column' => $column,
            'value' => $this->normalizeErrorValue($value),
            'message' => $message,
        ];
    }

    /**
     * @param array<int, array{column:?string, value:?string, message:string}> $rowErrors
     * @param callable(): mixed $callback
     */
    private function captureField(callable $callback, array &$rowErrors): mixed
    {
        try {
            return $callback();
        } catch (TimetableImportRowException $exception) {
            $this->addRowError(
                $rowErrors,
                $exception->column,
                $exception->getMessage(),
                $exception->value
            );

            return null;
        }
    }

    /**
     * @param array<int, array{row:int, column:?string, value:?string, message:string}> $errors
     * @param array<int, array{column:?string, value:?string, message:string}> $rowErrors
     */
    private function appendRowErrors(array &$errors, int $rowNumber, array $rowErrors): void
    {
        foreach ($rowErrors as $rowError) {
            $errors[] = [
                'row' => $rowNumber,
                'column' => $rowError['column'],
                'value' => $rowError['value'],
                'message' => $rowError['message'],
            ];
        }
    }

    private function normalizeErrorValue(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }

        $stringValue = trim((string) $value);

        return $stringValue === '' ? null : $stringValue;
    }
}
