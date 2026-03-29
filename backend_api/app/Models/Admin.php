<?php

namespace App\Models;

use Illuminate\Notifications\Notifiable;
use MongoDB\Laravel\Auth\User as Authenticatable;
use PHPOpenSourceSaver\JWTAuth\Contracts\JWTSubject;

class Admin extends Authenticatable implements JWTSubject
{
    use Notifiable;

    protected $connection = 'mongodb';

    protected $collection = 'admins';

    protected $fillable = [
        'email',
        'passwordHash',
        'role',
        'token_type',
    ];

    protected $hidden = [
        'passwordHash',
    ];

    public function getAuthPassword(): string
    {
        return (string) $this->passwordHash;
    }

    public function getJWTIdentifier(): mixed
    {
        return $this->getKey();
    }

    public function getJWTCustomClaims(): array
    {
        return ['token_type' => 'admin'];
    }
}
