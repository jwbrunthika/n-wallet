<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class LectureSession extends Model
{
    public const DELIVERY_MODE_WEEKDAY = 'WEEKDAY';
    public const DELIVERY_MODE_WEEKEND = 'WEEKEND';
    public const DELIVERY_MODE_BOTH = 'BOTH';
    public const DELIVERY_MODES = [
        self::DELIVERY_MODE_WEEKDAY,
        self::DELIVERY_MODE_WEEKEND,
        self::DELIVERY_MODE_BOTH,
    ];

    protected $connection = 'mongodb';

    protected $collection = 'sessions';

    protected $fillable = [
        'sessionDate',
        'startTime',
        'endTime',
        'courseCode',
        'moduleCode',
        'moduleName',
        'hallId',
        'attendanceOpenMinutesBefore',
        'attendanceCloseMinutesAfter',
        'batch',
        'deliveryMode',
        'lecturerEmail',
        'notes',
    ];

    protected $casts = [
        'attendanceOpenMinutesBefore' => 'integer',
        'attendanceCloseMinutesAfter' => 'integer',
    ];
}
