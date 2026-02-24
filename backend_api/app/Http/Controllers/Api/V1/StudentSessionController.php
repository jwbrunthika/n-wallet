<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Beacon;
use App\Models\LectureSession;
use App\Models\Student;
use App\Services\AcademicProfileService;
use Illuminate\Http\Request;

class StudentSessionController extends ApiController
{
    public function __construct(private readonly AcademicProfileService $academicProfileService)
    {
    }

    public function today(Request $request)
    {
        $payload = $request->validate([
            'date' => ['nullable', 'date_format:Y-m-d'],
        ]);

        /** @var Student $student */
        $student = $request->user();
        $this->academicProfileService->assertStudentHasAcademicProfile($student);

        $date = $payload['date'] ?? now()->format('Y-m-d');

        $sessions = LectureSession::query()
            ->where('sessionDate', $date)
            ->where('courseCode', strtoupper((string) $student->courseCode))
            ->orderBy('startTime')
            ->get()
            ->filter(fn (LectureSession $session): bool => $this->academicProfileService->isSessionAssignedToStudent($student, $session))
            ->map(fn (LectureSession $session): array => $this->mapSession($session))
            ->values();

        return $this->success($sessions);
    }

    public function show(Request $request, string $sessionId)
    {
        $session = LectureSession::query()->find($sessionId);
        if (! $session) {
            return $this->error('SESSION_NOT_FOUND', 'Session not found.', null, 404);
        }

        /** @var Student $student */
        $student = $request->user();
        $this->academicProfileService->assertStudentHasAcademicProfile($student);

        if (! $this->academicProfileService->isSessionAssignedToStudent($student, $session)) {
            return $this->error(
                'SESSION_NOT_ASSIGNED',
                'This session is not assigned to your course/batch/mode.',
                null,
                403
            );
        }

        return $this->success($this->mapSession($session));
    }

    private function mapSession(LectureSession $session): array
    {
        $beacon = Beacon::query()
            ->where('hallId', (string) $session->hallId)
            ->where('enabled', true)
            ->first();

        return [
            'id' => (string) $session->_id,
            'sessionDate' => $session->sessionDate,
            'startTime' => $session->startTime,
            'endTime' => $session->endTime,
            'courseCode' => $session->courseCode,
            'moduleCode' => $session->moduleCode,
            'moduleName' => $session->moduleName,
            'hallId' => $session->hallId,
            'batch' => $session->batch,
            'deliveryMode' => $session->deliveryMode ?? LectureSession::DELIVERY_MODE_BOTH,
            'lecturerEmail' => $session->lecturerEmail,
            'notes' => $session->notes,
            'attendanceOpenMinutesBefore' => (int) $session->attendanceOpenMinutesBefore,
            'attendanceCloseMinutesAfter' => (int) $session->attendanceCloseMinutesAfter,
            'expectedBeacon' => $beacon ? [
                'uuid' => $beacon->uuid,
                'major' => (int) $beacon->major,
                'minor' => (int) $beacon->minor,
            ] : null,
        ];
    }
}
