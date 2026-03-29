<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\AttendanceRecord;
use App\Models\Student;
use App\Services\AcademicProfileService;
use App\Services\AuditLogService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

class AdminStudentController extends ApiController
{
    public function __construct(
        private readonly AuditLogService $auditLogService,
        private readonly AcademicProfileService $academicProfileService,
    ) {
    }

    public function index(Request $request)
    {
        $payload = $request->validate([
            'query' => ['nullable', 'string'],
            'enrollmentStatus' => ['nullable', 'string'],
        ]);

        $query = Student::query();

        if (! empty($payload['query'])) {
            $query->where('email', 'like', '%'.$payload['query'].'%');
        }

        if (! empty($payload['enrollmentStatus'])) {
            $query->where('enrollmentStatus', $payload['enrollmentStatus']);
        }

        $students = $query->orderBy('email')->get()->map(fn (Student $student): array => $this->mapStudent($student))->values();

        return $this->success($students);
    }

    public function show(string $email)
    {
        $student = Student::query()->where('email', urldecode($email))->first();
        if (! $student) {
            return $this->error('STUDENT_NOT_FOUND', 'Student not found.', null, 404);
        }

        return $this->success([
            'email' => $student->email,
            'name' => $student->name,
            'enrollmentStatus' => $student->enrollmentStatus,
            'courseCode' => $student->courseCode,
            'batch' => $student->batch,
            'studyMode' => $student->studyMode,
            'faceTemplate' => [
                'algo' => $student->faceTemplate['algo'] ?? null,
                'modelVersion' => $student->faceTemplate['modelVersion'] ?? null,
                'createdAt' => $student->faceTemplate['createdAt'] ?? null,
            ],
            'enrollmentImageCount' => count($student->enrollmentImages ?? []),
        ]);
    }

    public function update(Request $request, string $email)
    {
        return $this->guarded(function () use ($request, $email) {
            $student = Student::query()->where('email', urldecode($email))->first();
            if (! $student) {
                return $this->error('STUDENT_NOT_FOUND', 'Student not found.', null, 404);
            }

            $payload = $request->validate([
                'email' => ['required', 'email', 'max:255'],
                'name' => ['nullable', 'string', 'max:255'],
            ]);

            $oldEmail = (string) $student->email;
            $newEmail = strtolower(trim((string) $payload['email']));
            $newName = isset($payload['name']) ? trim((string) $payload['name']) : null;
            if ($newName === '') {
                $newName = null;
            }

            $duplicateStudent = Student::query()
                ->where('email', $newEmail)
                ->where('_id', '!=', $student->_id)
                ->first();
            if ($duplicateStudent) {
                return $this->error(
                    'STUDENT_EMAIL_EXISTS',
                    'Student with this email already exists.',
                    ['email' => $newEmail],
                    422
                );
            }

            if ($oldEmail !== $newEmail) {
                $this->moveEnrollmentFilesForEmailChange($oldEmail, $newEmail, $student);
                AttendanceRecord::query()
                    ->where('studentEmail', $oldEmail)
                    ->update(['studentEmail' => $newEmail]);
                $student->email = $newEmail;
            }

            $student->name = $newName;
            $student->save();

            $this->auditLogService->log(
                (string) $request->user()->_id,
                'student_update',
                'student',
                (string) $student->_id,
                "Student updated by admin: {$oldEmail} -> {$student->email}"
            );

            return $this->success($this->mapStudent($student));
        });
    }

    public function destroy(Request $request, string $email)
    {
        return $this->guarded(function () use ($request, $email) {
            $student = Student::query()->where('email', urldecode($email))->first();
            if (! $student) {
                return $this->error('STUDENT_NOT_FOUND', 'Student not found.', null, 404);
            }

            $studentEmail = (string) $student->email;
            $enrollmentDir = 'enrollments/'.$studentEmail;
            if (Storage::disk('local')->exists($enrollmentDir)) {
                Storage::disk('local')->deleteDirectory($enrollmentDir);
            }

            $attendanceCount = AttendanceRecord::query()
                ->where('studentEmail', $studentEmail)
                ->count();

            $student->delete();

            $this->auditLogService->log(
                (string) $request->user()->_id,
                'student_delete',
                'student',
                (string) $student->_id,
                "Student deleted by admin: {$studentEmail}"
            );

            return $this->success([
                'deleted' => true,
                'retainedAttendanceRecords' => $attendanceCount,
            ]);
        });
    }

    public function updateAcademicProfile(Request $request, string $email)
    {
        return $this->guarded(function () use ($request, $email) {
            $student = Student::query()->where('email', urldecode($email))->first();
            if (! $student) {
                return $this->error('STUDENT_NOT_FOUND', 'Student not found.', null, 404);
            }

            $payload = $request->validate([
                'courseCode' => ['nullable', 'string', 'max:32'],
                'batch' => ['nullable', 'string', 'max:64'],
                'studyMode' => ['nullable', Rule::in(Student::STUDY_MODES)],
            ]);

            $isClearRequest = ($payload['courseCode'] ?? null) === null
                && ($payload['batch'] ?? null) === null
                && ($payload['studyMode'] ?? null) === null;

            if ($isClearRequest) {
                $student->courseCode = null;
                $student->batch = null;
                $student->studyMode = null;
                $student->save();

                $this->auditLogService->log(
                    (string) $request->user()->_id,
                    'student_academic_profile_cleared',
                    'student',
                    (string) $student->_id,
                    'Student academic profile cleared by admin'
                );

                return $this->success(['updated' => true, 'profile' => null]);
            }

            if (! isset($payload['courseCode'], $payload['batch'], $payload['studyMode'])) {
                return $this->error(
                    'ACADEMIC_PROFILE_INVALID',
                    'courseCode, batch and studyMode must be provided together, or all null to clear.',
                    null,
                    422
                );
            }

            $validated = $this->academicProfileService->validateProfilePayload(
                (string) $payload['courseCode'],
                (string) $payload['batch'],
                (string) $payload['studyMode']
            );

            $student->courseCode = $validated['courseCode'];
            $student->batch = $validated['batch'];
            $student->studyMode = $validated['studyMode'];
            $student->save();

            $this->auditLogService->log(
                (string) $request->user()->_id,
                'student_academic_profile_updated',
                'student',
                (string) $student->_id,
                'Student academic profile updated by admin'
            );

            return $this->success([
                'updated' => true,
                'profile' => [
                    'courseCode' => $student->courseCode,
                    'batch' => $student->batch,
                    'studyMode' => $student->studyMode,
                ],
            ]);
        });
    }

    public function resetEnrollment(Request $request, string $email)
    {
        return $this->guarded(function () use ($request, $email) {
            $student = Student::query()->where('email', urldecode($email))->first();
            if (! $student) {
                return $this->error('STUDENT_NOT_FOUND', 'Student not found.', null, 404);
            }

            $student->enrollmentStatus = Student::STATUS_NOT_ENROLLED;
            $student->faceTemplate = null;
            $student->enrollmentImages = [];
            $student->save();

            $this->auditLogService->log(
                (string) $request->user()->_id,
                'enrollment_reset',
                'student',
                (string) $student->_id,
                'Enrollment reset by admin'
            );

            return $this->success(['reset' => true]);
        });
    }

    public function enrollmentImages(Request $request, string $email)
    {
        $student = Student::query()->where('email', urldecode($email))->first();
        if (! $student) {
            return $this->error('STUDENT_NOT_FOUND', 'Student not found.', null, 404);
        }

        $appUrl = rtrim((string) config('app.url'), '/');

        $images = collect($student->enrollmentImages ?? [])->map(function (array $image) use ($appUrl, $student): array {
            $filename = basename((string) ($image['path'] ?? ''));

            return [
                'path' => $image['path'] ?? null,
                'qualityScore' => $image['qualityScore'] ?? null,
                'createdAt' => $image['createdAt'] ?? null,
                'url' => $appUrl.'/api/v1/admin/files/enrollments/'.urlencode((string) $student->email).'/'.urlencode($filename),
            ];
        })->values();

        $this->auditLogService->log(
            (string) $request->user()->_id,
            'view_enrollment_images',
            'student',
            (string) $student->_id,
            'Admin viewed enrollment image list'
        );

        return $this->success($images);
    }

    private function mapStudent(Student $student): array
    {
        return [
            'email' => $student->email,
            'name' => $student->name,
            'enrollmentStatus' => $student->enrollmentStatus,
            'courseCode' => $student->courseCode,
            'batch' => $student->batch,
            'studyMode' => $student->studyMode,
        ];
    }

    private function moveEnrollmentFilesForEmailChange(string $oldEmail, string $newEmail, Student $student): void
    {
        $disk = Storage::disk('local');
        $oldDir = 'enrollments/'.$oldEmail;
        $newDir = 'enrollments/'.$newEmail;

        if ($disk->exists($oldDir)) {
            if ($disk->exists($newDir)) {
                throw new \RuntimeException('Enrollment directory already exists for target email.');
            }

            $files = $disk->allFiles($oldDir);
            foreach ($files as $oldPath) {
                $suffix = ltrim(substr($oldPath, strlen($oldDir)), '/');
                $newPath = $newDir.'/'.$suffix;

                $newParent = dirname($newPath);
                if ($newParent !== '.' && ! $disk->exists($newParent)) {
                    $disk->makeDirectory($newParent);
                }

                if (! $disk->move($oldPath, $newPath)) {
                    throw new \RuntimeException("Failed to move enrollment file {$oldPath}");
                }
            }

            if ($disk->exists($oldDir)) {
                $disk->deleteDirectory($oldDir);
            }
        }

        $oldPrefix = 'enrollments/'.$oldEmail.'/';
        $newPrefix = 'enrollments/'.$newEmail.'/';
        $student->enrollmentImages = collect($student->enrollmentImages ?? [])
            ->map(function (array $image) use ($oldPrefix, $newPrefix): array {
                $path = (string) ($image['path'] ?? '');
                if (str_starts_with($path, $oldPrefix)) {
                    $image['path'] = $newPrefix.substr($path, strlen($oldPrefix));
                }

                return $image;
            })
            ->values()
            ->all();
    }
}
