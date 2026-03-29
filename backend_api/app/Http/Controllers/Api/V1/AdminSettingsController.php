<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\AppSetting;
use Illuminate\Http\Request;

class AdminSettingsController extends ApiController
{
    public function show()
    {
        $settings = AppSetting::query()->where('key', 'global')->first();

        if (! $settings) {
            $settings = AppSetting::query()->create([
                'key' => 'global',
                'faceMatchThreshold' => (float) env('FACE_MATCH_THRESHOLD', 0.55),
                'beaconRssiThreshold' => (float) env('BEACON_RSSI_THRESHOLD', -70),
                'beaconStabilitySeconds' => (int) env('BEACON_STABILITY_SECONDS', 8),
            ]);
        }

        return $this->success([
            'faceMatchThreshold' => (float) $settings->faceMatchThreshold,
            'beaconRssiThreshold' => (float) $settings->beaconRssiThreshold,
            'beaconStabilitySeconds' => (int) $settings->beaconStabilitySeconds,
        ]);
    }

    public function update(Request $request)
    {
        $payload = $request->validate([
            'faceMatchThreshold' => ['nullable', 'numeric', 'min:0', 'max:1'],
            'beaconRssiThreshold' => ['nullable', 'numeric'],
            'beaconStabilitySeconds' => ['nullable', 'integer', 'min:1', 'max:120'],
        ]);

        $settings = AppSetting::query()->firstOrCreate(['key' => 'global'], [
            'faceMatchThreshold' => (float) env('FACE_MATCH_THRESHOLD', 0.55),
            'beaconRssiThreshold' => (float) env('BEACON_RSSI_THRESHOLD', -70),
            'beaconStabilitySeconds' => (int) env('BEACON_STABILITY_SECONDS', 8),
        ]);

        foreach ($payload as $key => $value) {
            $settings->{$key} = $value;
        }

        $settings->save();

        return $this->success([
            'faceMatchThreshold' => (float) $settings->faceMatchThreshold,
            'beaconRssiThreshold' => (float) $settings->beaconRssiThreshold,
            'beaconStabilitySeconds' => (int) $settings->beaconStabilitySeconds,
        ]);
    }
}
