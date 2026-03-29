<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\CourseModule;
use App\Models\LectureSession;
use App\Models\Student;
use App\Models\UniversityCourse;
use App\Services\AuditLogService;
use App\Support\ApiException;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AdminCourseController extends ApiController
{
    public function __construct(private readonly AuditLogService $auditLogService)
    {
    }

    public function index()
    {
        $courses = UniversityCourse::query()
            ->orderBy('courseCode')
            ->get()
            ->map(fn (UniversityCourse $course): array => $this->mapCourse($course))
            ->values();

        return $this->success($courses);
    }

    public function store(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $payload = $request->validate([
                'courseName' => ['required', 'string', 'max:255'],
                'deliveryMode' => ['required', Rule::in(UniversityCourse::DELIVERY_MODES)],
                'batchCount' => ['required', 'integer', 'min:1', 'max:50'],
                'batchLabels' => ['nullable', 'array'],
                'batchLabels.*' => ['required', 'string', 'max:64'],
                'moduleCodes' => ['nullable', 'array'],
                'moduleCodes.*' => ['required', 'string', 'max:32'],
                'enabled' => ['nullable', 'boolean'],
            ]);

            $duplicateName = UniversityCourse::query()
                ->where('courseName', trim((string) $payload['courseName']))
                ->first();
            if ($duplicateName) {
                throw new ApiException('COURSE_NAME_EXISTS', 'courseName already exists.', 422);
            }

            $normalized = $this->normalizePayload($payload, null);
            $course = UniversityCourse::query()->create($normalized);

            $this->auditLogService->log(
                (string) $request->user()->_id,
                'course_create',
                'course',
                (string) $course->_id,
                'Course created by admin'
            );

            return $this->success($this->mapCourse($course), 201);
        });
    }

    public function show(string $id)
    {
        $course = UniversityCourse::query()->find($id);
        if (! $course) {
            return $this->error('COURSE_NOT_FOUND', 'Course not found.', null, 404);
        }

        return $this->success($this->mapCourse($course));
    }

    public function update(Request $request, string $id)
    {
        return $this->guarded(function () use ($request, $id) {
            $course = UniversityCourse::query()->find($id);
            if (! $course) {
                return $this->error('COURSE_NOT_FOUND', 'Course not found.', null, 404);
            }

            $payload = $request->validate([
                'courseName' => ['required', 'string', 'max:255'],
                'deliveryMode' => ['required', Rule::in(UniversityCourse::DELIVERY_MODES)],
                'batchCount' => ['required', 'integer', 'min:1', 'max:50'],
                'batchLabels' => ['nullable', 'array'],
                'batchLabels.*' => ['required', 'string', 'max:64'],
                'moduleCodes' => ['nullable', 'array'],
                'moduleCodes.*' => ['required', 'string', 'max:32'],
                'enabled' => ['nullable', 'boolean'],
            ]);

            $duplicateName = UniversityCourse::query()
                ->where('courseName', trim((string) $payload['courseName']))
                ->where('_id', '!=', $course->_id)
                ->first();
            if ($duplicateName) {
                throw new ApiException('COURSE_NAME_EXISTS', 'courseName already exists.', 422);
            }

            $normalized = $this->normalizePayload($payload, $course);
            $course->fill($normalized);
            $course->save();

            $this->auditLogService->log(
                (string) $request->user()->_id,
                'course_update',
                'course',
                (string) $course->_id,
                'Course updated by admin'
            );

            return $this->success($this->mapCourse($course));
        });
    }

    public function destroy(Request $request, string $id)
    {
        return $this->guarded(function () use ($request, $id) {
            $course = UniversityCourse::query()->find($id);
            if (! $course) {
                return $this->error('COURSE_NOT_FOUND', 'Course not found.', null, 404);
            }

            $courseCode = (string) $course->courseCode;
            $sessionCount = LectureSession::query()->where('courseCode', $courseCode)->count();
            $studentCount = Student::query()->where('courseCode', $courseCode)->count();

            if ($sessionCount > 0 || $studentCount > 0) {
                throw new ApiException(
                    'COURSE_IN_USE',
                    'Course cannot be deleted while sessions or students are linked to it.',
                    409,
                    [
                        'linkedSessions' => $sessionCount,
                        'linkedStudents' => $studentCount,
                    ]
                );
            }

            $course->delete();

            $this->auditLogService->log(
                (string) $request->user()->_id,
                'course_delete',
                'course',
                (string) $course->_id,
                'Course deleted by admin'
            );

            return $this->success(['deleted' => true]);
        });
    }

    /**
     * @param array<string, mixed> $payload
     * @param UniversityCourse|null $existingCourse
     * @return array<string, mixed>
     */
    private function normalizePayload(array $payload, ?UniversityCourse $existingCourse): array
    {
        $courseName = trim((string) $payload['courseName']);
        $deliveryMode = strtoupper(trim((string) $payload['deliveryMode']));
        $batchCount = (int) $payload['batchCount'];
        $enabled = (bool) ($payload['enabled'] ?? true);
        $courseCode = $existingCourse?->courseCode ?: $this->generateCourseCode();

        $moduleCodes = collect($payload['moduleCodes'] ?? [])
            ->map(fn (mixed $value): string => strtoupper(trim((string) $value)))
            ->filter(fn (string $value): bool => $value !== '')
            ->unique()
            ->values()
            ->all();

        if ($moduleCodes !== []) {
            $existingCodes = CourseModule::query()
                ->whereIn('moduleCode', $moduleCodes)
                ->pluck('moduleCode')
                ->map(fn (mixed $value): string => strtoupper((string) $value))
                ->all();

            $missingCodes = array_values(array_diff($moduleCodes, $existingCodes));
            foreach ($missingCodes as $missingCode) {
                CourseModule::query()->firstOrCreate(
                    ['moduleCode' => $missingCode],
                    [
                        'moduleCode' => $missingCode,
                        'moduleName' => "Module {$missingCode}",
                        'leaderAdminId' => null,
                    ]
                );
            }
        }

        $batchLabels = collect($payload['batchLabels'] ?? [])
            ->map(fn (mixed $value): string => trim((string) $value))
            ->filter(fn (string $value): bool => $value !== '')
            ->unique()
            ->values()
            ->all();

        if ($batchLabels === []) {
            $batchLabels = [];
            for ($i = 1; $i <= $batchCount; $i++) {
                $batchLabels[] = sprintf('Batch-%02d', $i);
            }
        } else {
            $batchCount = count($batchLabels);
        }

        return [
            'courseCode' => $courseCode,
            'courseName' => $courseName,
            'deliveryMode' => $deliveryMode,
            'batchCount' => $batchCount,
            'batchLabels' => $batchLabels,
            'moduleCodes' => $moduleCodes,
            'enabled' => $enabled,
        ];
    }

    private function generateCourseCode(): string
    {
        $codes = UniversityCourse::query()
            ->pluck('courseCode')
            ->map(fn (mixed $value): string => strtoupper(trim((string) $value)))
            ->values()
            ->all();

        $max = 0;
        foreach ($codes as $code) {
            if (preg_match('/^CRS-(\d+)$/', $code, $matches) !== 1) {
                continue;
            }
            $max = max($max, (int) ($matches[1] ?? 0));
        }

        return sprintf('CRS-%04d', $max + 1);
    }

    private function mapCourse(UniversityCourse $course): array
    {
        return [
            'id' => (string) $course->_id,
            'courseCode' => (string) $course->courseCode,
            'courseName' => (string) $course->courseName,
            'deliveryMode' => (string) ($course->deliveryMode ?? UniversityCourse::MODE_BOTH),
            'batchCount' => (int) ($course->batchCount ?? 0),
            'batchLabels' => array_values($course->batchLabels ?? []),
            'moduleCodes' => array_values($course->moduleCodes ?? []),
            'enabled' => (bool) ($course->enabled ?? true),
        ];
    }
}
