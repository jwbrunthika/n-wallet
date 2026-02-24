<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class AuditLog extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'audit_logs';

    protected $fillable = [
        'actorAdminId',
        'action',
        'entityType',
        'entityId',
        'note',
    ];
}
