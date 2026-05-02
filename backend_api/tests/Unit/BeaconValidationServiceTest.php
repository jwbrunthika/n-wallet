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
            'distanceMeters' => 14.0,
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
            'distanceMeters' => 3.0,
        ], -70, 8);

        $this->assertFalse($result['passed']);
        $this->assertSame('BEACON_MISMATCH', $result['reasonCode']);
    }

    public function test_it_passes_when_distance_threshold_is_met(): void
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
            'durationSec' => 4,
            'distanceMeters' => 6.5,
        ], -70, 8, 10.0);

        $this->assertTrue($result['passed']);
        $this->assertNull($result['reasonCode']);
    }

    public function test_it_fails_when_duration_and_distance_are_below_threshold(): void
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
            'durationSec' => 4,
            'distanceMeters' => 12.4,
        ], -70, 8, 10.0);

        $this->assertFalse($result['passed']);
        $this->assertSame('BEACON_UNSTABLE', $result['reasonCode']);
    }

    public function test_it_fails_when_distance_is_missing_and_duration_is_below_threshold(): void
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
            'durationSec' => 4,
            'distanceMeters' => null,
        ], -70, 8, 10.0);

        $this->assertFalse($result['passed']);
        $this->assertSame('BEACON_UNSTABLE', $result['reasonCode']);
    }

    public function test_it_passes_when_any_expected_beacon_matches(): void
    {
        $service = new BeaconValidationService();
        $beacons = [
            new Beacon([
                'uuid' => 'first',
                'major' => 1,
                'minor' => 2,
                'hallId' => 'hall-1',
                'enabled' => true,
            ]),
            new Beacon([
                'uuid' => 'second',
                'major' => 3,
                'minor' => 4,
                'hallId' => 'hall-1',
                'enabled' => true,
            ]),
        ];

        $result = $service->validateAny($beacons, [
            'uuid' => 'second',
            'major' => 3,
            'minor' => 4,
            'avgRssi' => -62,
            'durationSec' => 9,
            'distanceMeters' => null,
        ], -70, 8);

        $this->assertTrue($result['passed']);
        $this->assertNull($result['reasonCode']);
    }

    public function test_it_fails_when_no_expected_beacon_matches(): void
    {
        $service = new BeaconValidationService();
        $beacons = [
            new Beacon([
                'uuid' => 'first',
                'major' => 1,
                'minor' => 2,
                'hallId' => 'hall-1',
                'enabled' => true,
            ]),
        ];

        $result = $service->validateAny($beacons, [
            'uuid' => 'unknown',
            'major' => 1,
            'minor' => 2,
            'avgRssi' => -62,
            'durationSec' => 9,
            'distanceMeters' => null,
        ], -70, 8);

        $this->assertFalse($result['passed']);
        $this->assertSame('BEACON_MISMATCH', $result['reasonCode']);
    }

    public function test_it_keeps_threshold_failure_for_matching_beacon(): void
    {
        $service = new BeaconValidationService();
        $beacons = [
            new Beacon([
                'uuid' => 'first',
                'major' => 1,
                'minor' => 2,
                'hallId' => 'hall-1',
                'enabled' => true,
            ]),
            new Beacon([
                'uuid' => 'second',
                'major' => 3,
                'minor' => 4,
                'hallId' => 'hall-1',
                'enabled' => true,
            ]),
        ];

        $result = $service->validateAny($beacons, [
            'uuid' => 'second',
            'major' => 3,
            'minor' => 4,
            'avgRssi' => -85,
            'durationSec' => 9,
            'distanceMeters' => null,
        ], -70, 8);

        $this->assertFalse($result['passed']);
        $this->assertSame('BEACON_WEAK', $result['reasonCode']);
    }

    public function test_it_fails_when_expected_beacon_list_is_empty(): void
    {
        $service = new BeaconValidationService();

        $result = $service->validateAny([], [
            'uuid' => 'second',
            'major' => 3,
            'minor' => 4,
            'avgRssi' => -62,
            'durationSec' => 9,
            'distanceMeters' => null,
        ], -70, 8);

        $this->assertFalse($result['passed']);
        $this->assertSame('BEACON_MISMATCH', $result['reasonCode']);
    }
}
