<?php

namespace Tests\Unit;

use App\Models\Beacon;
use App\Services\Attendance\BeaconValidationService;
use Tests\TestCase;

class BeaconValidationServiceTest extends TestCase
{
    public function test_it_passes_when_identity_and_thresholds_match(): void
    {
        $service = new BeaconValidationService();
        $beacon = new Beacon([
            'uuid' => 'abcd',
            'major' => 1,
            'minor' => 2,
            'hallId' => 'hall-1',
            'enabled' => true,
        ]);

        $result = $service->validate($beacon, [
            'uuid' => 'abcd',
            'major' => 1,
            'minor' => 2,
            'avgRssi' => -60,
            'durationSec' => 12,
        ], -70, 8);

        $this->assertTrue($result['passed']);
        $this->assertNull($result['reasonCode']);
    }

    public function test_it_fails_on_beacon_mismatch(): void
    {
        $service = new BeaconValidationService();
        $beacon = new Beacon([
            'uuid' => 'abcd',
            'major' => 1,
            'minor' => 2,
            'hallId' => 'hall-1',
            'enabled' => true,
        ]);

        $result = $service->validate($beacon, [
            'uuid' => 'different',
            'major' => 1,
            'minor' => 2,
            'avgRssi' => -60,
            'durationSec' => 12,
        ], -70, 8);

        $this->assertFalse($result['passed']);
        $this->assertSame('BEACON_MISMATCH', $result['reasonCode']);
    }
}
