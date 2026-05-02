<?php

namespace App\Services\Attendance;

use App\Models\LectureSession;
use Carbon\Carbon;
use Carbon\CarbonInterface;

class AttendanceWindowService
{
    public function timezone(): string
    {
        $timezone = trim((string) config('attendance.timezone', ''));

        return $timezone !== '' ? $timezone : 'Asia/Colombo';
    }

    public function isInside(LectureSession $session, ?CarbonInterface $now = null): bool
    {
        $window = $this->window($session);
        $open = $window['open'];
        $close = $window['close'];

        if (! $close->isAfter($open)) {
            return false;
        }

        $current = $now
            ? Carbon::instance($now)->setTimezone($this->timezone())
            : Carbon::now($this->timezone());

        return $current->between($open, $close);
    }

    /**
     * @return array{open: Carbon, close: Carbon}
     */
    public function window(LectureSession $session): array
    {
        $timezone = $this->timezone();
        $sessionStart = Carbon::parse($session->sessionDate.' '.$session->startTime, $timezone);
        $sessionEnd = Carbon::parse($session->sessionDate.' '.$session->endTime, $timezone);

        return [
            'open' => $sessionStart->copy()->addMinutes((int) $session->attendanceOpenMinutesBefore),
            'close' => $sessionEnd->copy()->subMinutes((int) $session->attendanceCloseMinutesAfter),
        ];
    }
}
