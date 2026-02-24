<?php

namespace App\Services\Attendance;

use App\Models\Beacon;

class BeaconValidationService
{
    /**
     * @param array{uuid:string,major:int,minor:int,avgRssi:float,durationSec:int} $evidence
     */
    public function validate(Beacon $expectedBeacon, array $evidence, float $rssiThreshold, int $stabilitySeconds): array
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

        if ((int) ($evidence['durationSec'] ?? 0) < $stabilitySeconds) {
            return ['passed' => false, 'reasonCode' => 'BEACON_UNSTABLE'];
        }

        return ['passed' => true, 'reasonCode' => null];
    }
}
