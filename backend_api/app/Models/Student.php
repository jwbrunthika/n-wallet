<?php

namespace App\Models;

use Illuminate\Notifications\Notifiable;
use MongoDB\Laravel\Auth\User as Authenticatable;
use PHPOpenSourceSaver\JWTAuth\Contracts\JWTSubject;

class Student extends Authenticatable implements JWTSubject
{
    use Notifiable;

    public const STATUS_NOT_ENROLLED = 'NOT_ENROLLED';
    public const STATUS_ENROLLED = 'ENROLLED';
    public const STATUS_FAILED = 'FAILED';
    public const STUDY_MODE_WEEKDAY = 'WEEKDAY';
    public const STUDY_MODE_WEEKEND = 'WEEKEND';
    public const STUDY_MODES = [
        self::STUDY_MODE_WEEKDAY,
        self::STUDY_MODE_WEEKEND,
    ];

    protected $connection = 'mongodb';

    protected $collection = 'students';

    protected $fillable = [
        'email',
        'name',
        'enrollmentStatus',
        'faceTemplate',
        'enrollmentImages',
        'token_type',
        'phone',
        'courseCode',
        'batch',
        'studyMode',
    ];

    protected $casts = [
        'faceTemplate' => 'array',
        'enrollmentImages' => 'array',
    ];

    public function getJWTIdentifier(): mixed
    {
        return $this->getKey();
    }

    public function getJWTCustomClaims(): array
    {
        return ['token_type' => 'student'];
    }
}
