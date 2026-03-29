<?php

namespace Database\Seeders;

use App\Models\AppSetting;
use Illuminate\Database\Seeder;

class SettingSeeder extends Seeder
{
    public function run(): void
    {
        AppSetting::query()->updateOrCreate(
            ['key' => 'global'],
            [
                'faceMatchThreshold' => (float) env('FACE_MATCH_THRESHOLD', 0.55),
                'beaconRssiThreshold' => (float) env('BEACON_RSSI_THRESHOLD', -70),
                'beaconStabilitySeconds' => (int) env('BEACON_STABILITY_SECONDS', 8),
            ]
        );
    }
}
