<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\AttendanceRecord;
use App\Models\LectureSession;
use Illuminate\Http\Request;

class AdminAttendanceController extends ApiController
{
    public function logs(Request $request)
    {
        $payload = $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d'],
            'moduleCode' => ['nullable', 'string'],
            'hallId' => ['nullable', 'string'],
        ]);

        $records = AttendanceRecord::query()->orderByDesc('created_at')->get();

        $data = $records
            ->map(function (AttendanceRecord $record): array {
                $session = LectureSession::query()->find($record->sessionId);

                return [
                    'id' => (string) $record->_id,
                    'studentEmail' => $record->studentEmail,
                    'sessionId' => $record->sessionId,
                    'status' => $record->status,
                    'faceScore' => (float) $record->faceScore,
                    'beaconAvgRssi' => (float) $record->beaconAvgRssi,
                    'reasonCode' => $record->reasonCode,
                    'createdAt' => optional($record->created_at)?->toIso8601String(),
                    'session' => $session ? [
                        'sessionDate' => $session->sessionDate,
                        'moduleCode' => $session->moduleCode,
                        'moduleName' => $session->moduleName,
                        'hallId' => $session->hallId,
                    ] : null,
                ];
            })
            ->filter(function (array $row) use ($payload): bool {
                $session = $row['session'];
                if (! $session) {
                    return false;
                }

                if (isset($payload['from']) && $session['sessionDate'] < $payload['from']) {
                    return false;
                }
                if (isset($payload['to']) && $session['sessionDate'] > $payload['to']) {
                    return false;
                }
                if (! empty($payload['moduleCode']) && $session['moduleCode'] !== $payload['moduleCode']) {
                    return false;
                }
                if (! empty($payload['hallId']) && $session['hallId'] !== $payload['hallId']) {
                    return false;
                }

                return true;
            })
            ->values();

        return $this->success($data);
    }

    public function export(Request $request)
    {
        $response = $this->logs($request)->getData(true);
        $rows = $response['data'] ?? [];

        $csv = fopen('php://temp', 'r+');
        fputcsv($csv, ['studentEmail', 'sessionId', 'status', 'faceScore', 'beaconAvgRssi', 'reasonCode', 'sessionDate', 'moduleCode', 'hallId', 'createdAt']);

        foreach ($rows as $row) {
            fputcsv($csv, [
                $row['studentEmail'] ?? '',
                $row['sessionId'] ?? '',
                $row['status'] ?? '',
                $row['faceScore'] ?? '',
                $row['beaconAvgRssi'] ?? '',
                $row['reasonCode'] ?? '',
                $row['session']['sessionDate'] ?? '',
                $row['session']['moduleCode'] ?? '',
                $row['session']['hallId'] ?? '',
                $row['createdAt'] ?? '',
            ]);
        }

        rewind($csv);
        $content = stream_get_contents($csv);
        fclose($csv);

        return response($content, 200, [
            'Content-Type' => 'text/csv',
            'Content-Disposition' => 'attachment; filename="attendance_export.csv"',
        ]);
    }
}
