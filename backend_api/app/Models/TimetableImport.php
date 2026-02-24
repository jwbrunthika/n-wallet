<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class TimetableImport extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'timetable_imports';

    protected $fillable = [
        'importId',
        'filename',
        'uploaderAdminId',
        'rowCount',
        'status',
        'errors',
    ];

    protected $casts = [
        'errors' => 'array',
    ];
}
