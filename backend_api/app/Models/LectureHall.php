<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class LectureHall extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'lecture_halls';

    protected $fillable = [
        'name',
    ];
}
