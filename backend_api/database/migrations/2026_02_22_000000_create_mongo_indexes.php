<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private array $collections = [
        'students',
        'admins',
        'otp_requests',
        'lecture_halls',
        'beacons',
        'modules',
        'sessions',
        'attendance_records',
        'timetable_imports',
        'audit_logs',
        'settings',
    ];

    public function up(): void
    {
        $db = DB::connection('mongodb')->getMongoDB();

        $existing = [];
        foreach ($db->listCollections() as $collectionInfo) {
            $existing[] = $collectionInfo->getName();
        }

        foreach ($this->collections as $collection) {
            if (! in_array($collection, $existing, true)) {
                $db->createCollection($collection);
            }
        }

        $db->selectCollection('students')->createIndex(['email' => 1], ['unique' => true]);
        $db->selectCollection('admins')->createIndex(['email' => 1], ['unique' => true]);

        $otpCollection = $db->selectCollection('otp_requests');
        $otpCollection->createIndex(['otpRequestId' => 1], ['unique' => true]);
        $otpCollection->createIndex(['email' => 1]);
        $otpCollection->createIndex(['expiresAt' => 1], ['expireAfterSeconds' => 0]);

        $db->selectCollection('lecture_halls')->createIndex(['name' => 1], ['unique' => true]);

        $beaconCollection = $db->selectCollection('beacons');
        $beaconCollection->createIndex(['uuid' => 1, 'major' => 1, 'minor' => 1], ['unique' => true]);
        $beaconCollection->createIndex(['hallId' => 1], ['unique' => true]);

        $db->selectCollection('modules')->createIndex(['moduleCode' => 1], ['unique' => true]);

        $sessionCollection = $db->selectCollection('sessions');
        $sessionCollection->createIndex(['sessionDate' => 1]);
        $sessionCollection->createIndex(['moduleCode' => 1]);
        $sessionCollection->createIndex(['hallId' => 1]);

        $attendanceCollection = $db->selectCollection('attendance_records');
        $attendanceCollection->createIndex(['studentEmail' => 1, 'sessionId' => 1], ['unique' => true]);
        $attendanceCollection->createIndex(['created_at' => 1]);

        $db->selectCollection('timetable_imports')->createIndex(['created_at' => 1]);
        $db->selectCollection('audit_logs')->createIndex(['created_at' => 1]);

        $settingsCollection = $db->selectCollection('settings');
        $settingsCollection->createIndex(['key' => 1], ['unique' => true]);
    }

    public function down(): void
    {
        $db = DB::connection('mongodb')->getMongoDB();

        foreach ($this->collections as $collection) {
            $db->dropCollection($collection);
        }
    }
};
