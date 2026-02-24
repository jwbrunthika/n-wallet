<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\AttendanceRecord;
use App\Models\Student;
use App\Services\AttendanceDecisionService;
use Illuminate\Http\Request;

class StudentAttendanceController extends ApiController
{
    public function __construct(private readonly AttendanceDecisionService $attendanceDecisionService)
    {
    }

    public function submit(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $request->validate([
                'sessionId' => ['required', 'string'],
                'faceFrames' => ['required', 'array', 'min:1', 'max:3'],
                'faceFrames.*' => ['required', 'image', 'max:5120'],
                'beaconEvidence' => ['required', 'string'],
            ]);

            $beaconEvidence = json_decode((string) $request->input('beaconEvidence'), true);
            if (! is_array($beaconEvidence)) {
                return $this->error('INVALID_BEACON_EVIDENCE', 'Beacon evidence must be valid JSON.', null, 422);
            }

            $normalizedEvidence = [
                'uuid' => strtolower((string) ($beaconEvidence['uuid'] ?? '')),
                'major' => (int) ($beaconEvidence['major'] ?? -1),
                'minor' => (int) ($beaconEvidence['minor'] ?? -1),
                'avgRssi' => (float) ($beaconEvidence['avgRssi'] ?? -999),
                'durationSec' => (int) ($beaconEvidence['durationSec'] ?? 0),
            ];

            /** @var Student $student */
            $student = $request->user();

            $result = $this->attendanceDecisionService->submit(
                $student,
                (string) $request->input('sessionId'),
                $request->file('faceFrames', []),
                $normalizedEvidence
            );

            return $this->success($result);
        });
    }

    public function history(Request $request)
    {
        /** @var Student $student */
        $student = $request->user();

        $payload = $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d'],
        ]);

        $records = AttendanceRecord::query()
            ->where('studentEmail', $student->email)
            ->orderByDesc('created_at')
            ->get()
            ->filter(function (AttendanceRecord $record) use ($payload): bool {
                $date = optional($record->created_at)?->format('Y-m-d');
                if (! $date) {
                    return false;
                }

                if (isset($payload['from']) && $date < $payload['from']) {
                    return false;
                }
                if (isset($payload['to']) && $date > $payload['to']) {
                    return false;
                }

                return true;
            })
            ->map(fn (AttendanceRecord $record): array => [
                'id' => (string) $record->_id,
                'studentEmail' => $record->studentEmail,
                'sessionId' => $record->sessionId,
                'status' => $record->status,
                'faceScore' => (float) $record->faceScore,
                'beaconAvgRssi' => (float) $record->beaconAvgRssi,
                'reasonCode' => $record->reasonCode,
                'createdAt' => optional($record->created_at)?->toIso8601String(),
            ])
            ->values();

        return $this->success($records);
    }
}
