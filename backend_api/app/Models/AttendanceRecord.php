<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class AttendanceRecord extends Model
{
    public const STATUS_PRESENT = 'PRESENT';
    public const STATUS_REJECTED = 'REJECTED';

    protected $connection = 'mongodb';

    protected $collection = 'attendance_records';

    protected $fillable = [
        'studentEmail',
        'sessionId',
        'status',
        'faceScore',
        'beaconAvgRssi',
        'reasonCode',
    ];

    protected $casts = [
        'faceScore' => 'float',
        'beaconAvgRssi' => 'float',
    ];
}
