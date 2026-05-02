<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $beaconCollection = DB::connection('mongodb')->getMongoDB()->selectCollection('beacons');

        try {
            $beaconCollection->dropIndex('hallId_1');
        } catch (\Throwable) {
            // Index is absent or already recreated with the desired shape.
        }

        $beaconCollection->createIndex(['hallId' => 1], ['name' => 'hallId_1']);
    }

    public function down(): void
    {
        $beaconCollection = DB::connection('mongodb')->getMongoDB()->selectCollection('beacons');

        try {
            $beaconCollection->dropIndex('hallId_1');
        } catch (\Throwable) {
            // Index is absent.
        }

        $beaconCollection->createIndex(['hallId' => 1], ['unique' => true, 'name' => 'hallId_1']);
    }
};
