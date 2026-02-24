<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\LectureSession;
use Illuminate\Http\Request;

class AdminSessionController extends ApiController
{
    public function index(Request $request)
    {
        $payload = $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d'],
            'moduleCode' => ['nullable', 'string'],
            'courseCode' => ['nullable', 'string'],
            'batch' => ['nullable', 'string'],
            'deliveryMode' => ['nullable', 'string'],
        ]);

        $query = LectureSession::query()->orderByDesc('sessionDate')->orderBy('startTime');

        if (! empty($payload['moduleCode'])) {
            $query->where('moduleCode', (string) $payload['moduleCode']);
        }
        if (! empty($payload['courseCode'])) {
            $query->where('courseCode', strtoupper((string) $payload['courseCode']));
        }
        if (! empty($payload['batch'])) {
            $query->where('batch', (string) $payload['batch']);
        }
        if (! empty($payload['deliveryMode'])) {
            $query->where('deliveryMode', strtoupper((string) $payload['deliveryMode']));
        }

        $sessions = $query->get()
            ->filter(function (LectureSession $session) use ($payload): bool {
                if (isset($payload['from']) && $session->sessionDate < $payload['from']) {
                    return false;
                }
                if (isset($payload['to']) && $session->sessionDate > $payload['to']) {
                    return false;
                }

                return true;
            })
            ->map(fn (LectureSession $session): array => [
                'id' => (string) $session->_id,
                'sessionDate' => $session->sessionDate,
                'startTime' => $session->startTime,
                'endTime' => $session->endTime,
                'courseCode' => $session->courseCode,
                'moduleCode' => $session->moduleCode,
                'moduleName' => $session->moduleName,
                'hallId' => $session->hallId,
                'batch' => $session->batch,
                'deliveryMode' => $session->deliveryMode,
                'lecturerEmail' => $session->lecturerEmail,
                'notes' => $session->notes,
                'attendanceOpenMinutesBefore' => (int) $session->attendanceOpenMinutesBefore,
                'attendanceCloseMinutesAfter' => (int) $session->attendanceCloseMinutesAfter,
            ])
            ->values();

        return $this->success($sessions);
    }
}
