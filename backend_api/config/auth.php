<?php

return [
    'defaults' => [
        'guard' => env('AUTH_GUARD', 'student_api'),
        'passwords' => env('AUTH_PASSWORD_BROKER', 'admins'),
    ],

    'guards' => [
        'student_api' => [
            'driver' => 'jwt',
            'provider' => 'students',
        ],
        'admin_api' => [
            'driver' => 'jwt',
            'provider' => 'admins',
        ],
    ],

    'providers' => [
        'students' => [
            'driver' => 'eloquent',
            'model' => App\Models\Student::class,
        ],
        'admins' => [
            'driver' => 'eloquent',
            'model' => App\Models\Admin::class,
        ],
    ],

    'passwords' => [
        'admins' => [
            'provider' => 'admins',
            'table' => 'password_reset_tokens',
            'expire' => 60,
            'throttle' => 60,
        ],
    ],

    'password_timeout' => 10800,
];
