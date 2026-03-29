<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $db = DB::connection('mongodb')->getMongoDB();

        $existingCollections = [];
        foreach ($db->listCollections() as $collectionInfo) {
            $existingCollections[] = $collectionInfo->getName();
        }

        if (! in_array('courses', $existingCollections, true)) {
            $db->createCollection('courses');
        }

        $db->selectCollection('courses')->createIndex(['courseCode' => 1], ['unique' => true]);
        $db->selectCollection('courses')->createIndex(['enabled' => 1]);

        $students = $db->selectCollection('students');
        $students->createIndex(['courseCode' => 1]);
        $students->createIndex(['batch' => 1]);
        $students->createIndex(['studyMode' => 1]);

        $sessions = $db->selectCollection('sessions');
        $sessions->createIndex(['courseCode' => 1]);
        $sessions->createIndex(['batch' => 1]);
        $sessions->createIndex(['deliveryMode' => 1]);
    }

    public function down(): void
    {
        $db = DB::connection('mongodb')->getMongoDB();

        $db->selectCollection('courses')->dropIndex('courseCode_1');
        $db->selectCollection('courses')->dropIndex('enabled_1');
        $db->selectCollection('students')->dropIndex('courseCode_1');
        $db->selectCollection('students')->dropIndex('batch_1');
        $db->selectCollection('students')->dropIndex('studyMode_1');
        $db->selectCollection('sessions')->dropIndex('courseCode_1');
        $db->selectCollection('sessions')->dropIndex('batch_1');
        $db->selectCollection('sessions')->dropIndex('deliveryMode_1');
    }
};
