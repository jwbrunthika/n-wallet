<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class UniversityCourse extends Model
{
    public const MODE_WEEKDAY = 'WEEKDAY';
    public const MODE_WEEKEND = 'WEEKEND';
    public const MODE_BOTH = 'BOTH';
    public const DELIVERY_MODES = [
        self::MODE_WEEKDAY,
        self::MODE_WEEKEND,
        self::MODE_BOTH,
    ];

    protected $connection = 'mongodb';

    protected $collection = 'courses';

    protected $fillable = [
        'courseCode',
        'courseName',
        'deliveryMode',
        'batchCount',
        'batchLabels',
        'moduleCodes',
        'enabled',
    ];

    protected $casts = [
        'batchCount' => 'integer',
        'batchLabels' => 'array',
        'moduleCodes' => 'array',
        'enabled' => 'boolean',
    ];
}
