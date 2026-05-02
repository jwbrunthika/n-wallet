<?php

namespace Tests\Unit;

use App\Models\LectureSession;
use App\Services\Attendance\AttendanceWindowService;
use Carbon\Carbon;
use Tests\TestCase;

class AttendanceWindowServiceTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'app.timezone' => 'UTC',
            'attendance.timezone' => 'Asia/Colombo',
        ]);
    }

    public function test_it_uses_attendance_timezone_over_app_timezone(): void
    {
        $service = new AttendanceWindowService();

        $this->assertSame('Asia/Colombo', $service->timezone());
    }

    public function test_it_accepts_attendance_inside_colombo_window(): void
    {
        $service = new AttendanceWindowService();

        $this->assertTrue($service->isInside(
            $this->lectureSession(),
            Carbon::parse('2026-05-02 10:30:00', 'Asia/Colombo')
        ));
    }

    public function test_it_rejects_attendance_before_window_opens(): void
    {
        $service = new AttendanceWindowService();

        $this->assertFalse($service->isInside(
            $this->lectureSession(),
            Carbon::parse('2026-05-02 10:14:59', 'Asia/Colombo')
        ));
    }

    public function test_it_rejects_attendance_after_window_closes(): void
    {
        $service = new AttendanceWindowService();

        $this->assertFalse($service->isInside(
            $this->lectureSession(),
            Carbon::parse('2026-05-02 11:50:01', 'Asia/Colombo')
        ));
    }

    public function test_it_rejects_misconfigured_windows(): void
    {
        $service = new AttendanceWindowService();
        $session = $this->lectureSession([
            'attendanceOpenMinutesBefore' => 90,
            'attendanceCloseMinutesAfter' => 90,
        ]);

        $this->assertFalse($service->isInside(
            $session,
            Carbon::parse('2026-05-02 10:45:00', 'Asia/Colombo')
        ));
    }

    private function lectureSession(array $overrides = []): LectureSession
    {
        return new LectureSession(array_merge([
            'sessionDate' => '2026-05-02',
            'startTime' => '10:00',
            'endTime' => '12:00',
            'attendanceOpenMinutesBefore' => 15,
            'attendanceCloseMinutesAfter' => 10,
        ], $overrides));
    }
}
