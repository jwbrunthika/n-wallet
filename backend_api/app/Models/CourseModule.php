<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class CourseModule extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'modules';

    protected $fillable = [
        'moduleCode',
        'moduleName',
        'leaderAdminId',
    ];
}
