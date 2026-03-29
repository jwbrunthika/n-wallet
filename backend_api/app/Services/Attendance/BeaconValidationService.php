<?php

namespace App\Services\Attendance;

use App\Models\Beacon;

class BeaconValidationService
{
    /**
     * @param array{uuid:string,major:int,minor:int,avgRssi:float,durationSec:int,pingCount?:int} $evidence
     */
    public function validate(Beacon $expectedBeacon, array $evidence, float $rssiThreshold, int $stabilitySeconds, int $minPingCount = 5): array
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
        $pingCount = (int) ($evidence['pingCount'] ?? 0);
        if ($durationSec < $stabilitySeconds && $pingCount < $minPingCount) {
            return ['passed' => false, 'reasonCode' => 'BEACON_UNSTABLE'];
        }

        return ['passed' => true, 'reasonCode' => null];
    }
}
