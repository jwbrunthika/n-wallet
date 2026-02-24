<?php

namespace App\Services;

use App\Models\LectureSession;
use App\Models\Student;
use App\Models\UniversityCourse;
use App\Support\ApiException;

class AcademicProfileService
{
    public function assertStudentHasAcademicProfile(Student $student): void
    {
        if ($this->hasAcademicProfile($student)) {
            return;
        }

        throw new ApiException(
            'ACADEMIC_PROFILE_REQUIRED',
            'Academic profile is incomplete. Ask admin to assign course, batch, and study mode.',
            422
        );
    }

    public function hasAcademicProfile(Student $student): bool
    {
        return $this->normalize($student->courseCode) !== ''
            && $this->normalize($student->batch) !== ''
            && in_array($this->normalizeMode($student->studyMode), Student::STUDY_MODES, true);
    }

    /**
     * @return array{course:UniversityCourse,courseCode:string,batch:string,studyMode:string}
     */
    public function validateProfilePayload(string $courseCode, string $batch, string $studyMode): array
    {
        $normalizedCourseCode = strtoupper($this->normalize($courseCode));
        $normalizedBatch = $this->normalize($batch);
        $normalizedStudyMode = $this->normalizeMode($studyMode);

        if ($normalizedCourseCode === '' || $normalizedBatch === '' || $normalizedStudyMode === '') {
            throw new ApiException('ACADEMIC_PROFILE_INVALID', 'courseCode, batch and studyMode are required.', 422);
        }

        if (! in_array($normalizedStudyMode, Student::STUDY_MODES, true)) {
            throw new ApiException(
                'ACADEMIC_PROFILE_INVALID',
                'studyMode must be WEEKDAY or WEEKEND.',
                422
            );
        }

        $course = UniversityCourse::query()
            ->where('courseCode', $normalizedCourseCode)
            ->where('enabled', true)
            ->first();

        if (! $course) {
            throw new ApiException('COURSE_NOT_FOUND', 'Assigned course does not exist or is disabled.', 422);
        }

        $courseMode = $this->normalizeMode($course->deliveryMode) ?: UniversityCourse::MODE_BOTH;
        if ($courseMode !== UniversityCourse::MODE_BOTH && $courseMode !== $normalizedStudyMode) {
            throw new ApiException(
                'ACADEMIC_PROFILE_INVALID',
                "studyMode {$normalizedStudyMode} is not allowed for this course.",
                422
            );
        }

        $resolvedBatch = $this->resolveBatchForCourse($course, $normalizedBatch);
        if ($resolvedBatch === null) {
            throw new ApiException('ACADEMIC_PROFILE_INVALID', "batch {$normalizedBatch} is not configured for this course.", 422);
        }

        return [
            'course' => $course,
            'courseCode' => $normalizedCourseCode,
            'batch' => $resolvedBatch,
            'studyMode' => $normalizedStudyMode,
        ];
    }

    public function isSessionAssignedToStudent(Student $student, LectureSession $session): bool
    {
        if (! $this->hasAcademicProfile($student)) {
            return false;
        }

        $studentCourseCode = strtoupper($this->normalize($student->courseCode));
        $sessionCourseCode = strtoupper($this->normalize($session->courseCode));

        if ($studentCourseCode === '' || $studentCourseCode !== $sessionCourseCode) {
            return false;
        }

        $sessionBatch = $this->normalize($session->batch);
        $studentBatch = $this->normalize($student->batch);

        if ($sessionBatch !== '' && strcasecmp($sessionBatch, $studentBatch) !== 0) {
            return false;
        }

        $sessionMode = $this->normalizeMode($session->deliveryMode) ?: UniversityCourse::MODE_BOTH;
        $studentMode = $this->normalizeMode($student->studyMode);

        if ($sessionMode === UniversityCourse::MODE_BOTH) {
            return true;
        }

        return $sessionMode === $studentMode;
    }

    public function isBatchAllowedForCourse(UniversityCourse $course, string $batch): bool
    {
        return $this->resolveBatchForCourse($course, $batch) !== null;
    }

    public function isDeliveryModeAllowedForCourse(UniversityCourse $course, string $deliveryMode): bool
    {
        $deliveryMode = $this->normalizeMode($deliveryMode) ?: UniversityCourse::MODE_BOTH;
        $courseMode = $this->normalizeMode($course->deliveryMode) ?: UniversityCourse::MODE_BOTH;

        return $courseMode === UniversityCourse::MODE_BOTH || $courseMode === $deliveryMode;
    }

    private function normalize(?string $value): string
    {
        return trim((string) $value);
    }

    private function normalizeMode(?string $value): string
    {
        return strtoupper($this->normalize($value));
    }

    private function resolveBatchForCourse(UniversityCourse $course, string $batch): ?string
    {
        $batch = $this->normalize($batch);
        if ($batch === '') {
            return null;
        }

        $allowedBatches = collect($course->batchLabels ?? [])
            ->map(fn (mixed $value): string => $this->normalize((string) $value))
            ->filter(fn (string $value): bool => $value !== '')
            ->values()
            ->all();

        if ($allowedBatches === []) {
            return $batch;
        }

        foreach ($allowedBatches as $allowedBatch) {
            if (strcasecmp($allowedBatch, $batch) === 0) {
                return $allowedBatch;
            }
        }

        return null;
    }
}
