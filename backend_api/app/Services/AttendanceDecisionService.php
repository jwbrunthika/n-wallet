<?php

namespace App\Services;

use App\Models\AppSetting;
use App\Models\AttendanceRecord;
use App\Models\Beacon;
use App\Models\LectureSession;
use App\Models\Student;
use App\Services\Attendance\BeaconValidationService;
use App\Support\ApiException;
use Carbon\Carbon;

class AttendanceDecisionService
{
    public function __construct(
        private readonly IdentityVerificationService $identityVerificationService,
        private readonly BeaconValidationService $beaconValidationService,
        private readonly AcademicProfileService $academicProfileService,
    ) {
    }

    /**
     * @param array<int, UploadedFile> $faceFrames
     * @param array{uuid:string,major:int,minor:int,avgRssi:float,durationSec:int,distanceMeters?:?float} $beaconEvidence
     */
    public function submit(Student $student, string $sessionId, array $faceFrames, array $beaconEvidence): array
    {
        if ($student->enrollmentStatus !== Student::STATUS_ENROLLED || ! isset($student->faceTemplate['encryptedVector'])) {
            return $this->persistRejected($student->email, $sessionId, 0.0, (float) ($beaconEvidence['avgRssi'] ?? 0), 'NOT_ENROLLED');
        }

        $session = LectureSession::query()->find($sessionId);
        if (! $session) {
            throw new ApiException('SESSION_NOT_FOUND', 'Session not found.', 404);
        }

        if (! $this->academicProfileService->isSessionAssignedToStudent($student, $session)) {
            return $this->persistRejected(
                $student->email,
                (string) $session->_id,
                0.0,
                (float) ($beaconEvidence['avgRssi'] ?? 0),
                'SESSION_NOT_ASSIGNED'
            );
        }

        $duplicate = AttendanceRecord::query()
            ->where('studentEmail', $student->email)
            ->where('sessionId', (string) $session->_id)
            ->first();

        if ($duplicate) {
            throw new ApiException('DUPLICATE_ATTENDANCE', 'Attendance already submitted for this session.', 409);
        }

        if (! $this->isInsideAttendanceWindow($session)) {
            return $this->persistRejected($student->email, (string) $session->_id, 0.0, (float) ($beaconEvidence['avgRssi'] ?? 0), 'OUTSIDE_WINDOW');
        }

        $setting = AppSetting::query()->where('key', 'global')->first();
        $faceThreshold = (float) ($setting->faceMatchThreshold ?? env('FACE_MATCH_THRESHOLD', 0.55));
        $beaconRssiThreshold = (float) ($setting->beaconRssiThreshold ?? env('BEACON_RSSI_THRESHOLD', -70));
        $beaconStabilitySeconds = (int) ($setting->beaconStabilitySeconds ?? env('BEACON_STABILITY_SECONDS', 8));
        $beaconMaxDistanceMeters = (float) env('BEACON_MAX_DISTANCE_METERS', 10);

        $bestFaceScore = $this->identityVerificationService->bestFaceScore($student, $faceFrames);
        $facePass = $bestFaceScore >= $faceThreshold;

        $expectedBeacon = Beacon::query()
            ->where('hallId', (string) $session->hallId)
            ->where('enabled', true)
            ->first();

        if (! $expectedBeacon) {
            return $this->persistRejected(
                $student->email,
                (string) $session->_id,
                $bestFaceScore,
                (float) ($beaconEvidence['avgRssi'] ?? 0),
                'BEACON_MISMATCH'
            );
        }

        // Beacon evidence decision uses summarized client values only.
        // Backend requires exact beacon identity match plus threshold checks.
        $beaconDecision = $this->beaconValidationService->validate(
            $expectedBeacon,
            $beaconEvidence,
            $beaconRssiThreshold,
            $beaconStabilitySeconds,
            $beaconMaxDistanceMeters
        );

        if (! $facePass) {
            return $this->persistRejected($student->email, (string) $session->_id, $bestFaceScore, (float) ($beaconEvidence['avgRssi'] ?? 0), 'FACE_FAIL');
        }

        if (! $beaconDecision['passed']) {
            return $this->persistRejected(
                $student->email,
                (string) $session->_id,
                $bestFaceScore,
                (float) ($beaconEvidence['avgRssi'] ?? 0),
                (string) $beaconDecision['reasonCode']
            );
        }

        try {
            AttendanceRecord::query()->create([
                'studentEmail' => $student->email,
                'sessionId' => (string) $session->_id,
                'status' => AttendanceRecord::STATUS_PRESENT,
                'faceScore' => $bestFaceScore,
                'beaconAvgRssi' => (float) ($beaconEvidence['avgRssi'] ?? 0),
                'reasonCode' => null,
            ]);
        } catch (\Throwable $exception) {
            throw new ApiException('DUPLICATE_ATTENDANCE', 'Attendance already submitted for this session.', 409);
        }

        return [
            'status' => AttendanceRecord::STATUS_PRESENT,
            'faceScore' => $bestFaceScore,
        ];
    }

    private function isInsideAttendanceWindow(LectureSession $session): bool
    {
        $timezone = config('app.timezone', 'UTC');
        $sessionStart = Carbon::parse($session->sessionDate.' '.$session->startTime, $timezone);
        $sessionEnd = Carbon::parse($session->sessionDate.' '.$session->endTime, $timezone);

        // Stored field names are legacy, but current semantics are:
        // - attendanceOpenMinutesBefore => minutes after session start
        // - attendanceCloseMinutesAfter => minutes before session end
        $windowOpen = $sessionStart->copy()->addMinutes((int) $session->attendanceOpenMinutesBefore);
        $windowClose = $sessionEnd->copy()->subMinutes((int) $session->attendanceCloseMinutesAfter);

        $now = Carbon::now($timezone);

        return $now->between($windowOpen, $windowClose);
    }

    private function persistRejected(string $studentEmail, string $sessionId, float $faceScore, float $beaconAvgRssi, string $reasonCode): array
    {
        try {
            AttendanceRecord::query()->create([
                'studentEmail' => $studentEmail,
                'sessionId' => $sessionId,
                'status' => AttendanceRecord::STATUS_REJECTED,
                'faceScore' => $faceScore,
                'beaconAvgRssi' => $beaconAvgRssi,
                'reasonCode' => $reasonCode,
            ]);
        } catch (\Throwable $exception) {
            throw new ApiException('DUPLICATE_ATTENDANCE', 'Attendance already submitted for this session.', 409);
        }

        return [
            'status' => AttendanceRecord::STATUS_REJECTED,
            'faceScore' => $faceScore,
            'reasonCode' => $reasonCode,
        ];
    }
}
