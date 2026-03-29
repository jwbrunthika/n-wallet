<?php

namespace App\Services\Attendance;

use App\Models\Beacon;

class BeaconValidationService
{
    /**
     * @param array{uuid:string,major:int,minor:int,avgRssi:float,durationSec:int,distanceMeters?:?float} $evidence
     */
    public function validate(Beacon $expectedBeacon, array $evidence, float $rssiThreshold, int $stabilitySeconds, float $maxDistanceMeters = 10.0): array
    {
        if (
            strtolower((string) $expectedBeacon->uuid) !== strtolower((string) ($evidence['uuid'] ?? '')) ||
            (int) $expectedBeacon->major !== (int) ($evidence['major'] ?? -1) ||
            (int) $expectedBeacon->minor !== (int) ($evidence['minor'] ?? -1)
        ) {
            return ['passed' => false, 'reasonCode' => 'BEACON_MISMATCH'];
        }

        if ((float) ($evidence['avgRssi'] ?? -999) < $rssiThreshold) {
            return ['passed' => false, 'reasonCode' => 'BEACON_WEAK'];
        }

        $durationSec = (int) ($evidence['durationSec'] ?? 0);
        $distanceMeters = isset($evidence['distanceMeters']) ? (float) $evidence['distanceMeters'] : null;
        $distancePass = $distanceMeters !== null && $distanceMeters > 0 && $distanceMeters <= $maxDistanceMeters;

        if ($durationSec < $stabilitySeconds && ! $distancePass) {
            return ['passed' => false, 'reasonCode' => 'BEACON_UNSTABLE'];
        }

        return ['passed' => true, 'reasonCode' => null];
    }
}
