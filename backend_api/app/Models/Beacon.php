<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class Beacon extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'beacons';

    protected $fillable = [
        'uuid',
        'major',
        'minor',
        'hallId',
        'enabled',
    ];

    protected $casts = [
        'major' => 'integer',
        'minor' => 'integer',
        'enabled' => 'boolean',
    ];
}
