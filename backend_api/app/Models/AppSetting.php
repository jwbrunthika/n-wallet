<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class AppSetting extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'settings';

    protected $fillable = [
        'key',
        'faceMatchThreshold',
        'beaconRssiThreshold',
        'beaconStabilitySeconds',
    ];

    protected $casts = [
        'faceMatchThreshold' => 'float',
        'beaconRssiThreshold' => 'float',
        'beaconStabilitySeconds' => 'integer',
    ];
}
