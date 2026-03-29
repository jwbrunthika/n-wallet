<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class OtpRequest extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'otp_requests';

    public $timestamps = true;

    protected $fillable = [
        'otpRequestId',
        'email',
        'otpHash',
        'expiresAt',
        'resendAvailableAt',
        'attemptsLeft',
        'verifiedAt',
    ];

    protected $casts = [
        'expiresAt' => 'datetime',
        'resendAvailableAt' => 'datetime',
        'verifiedAt' => 'datetime',
    ];
}
