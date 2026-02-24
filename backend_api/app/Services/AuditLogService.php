<?php

namespace App\Services;

use App\Models\AuditLog;

class AuditLogService
{
    public function log(?string $actorAdminId, string $action, string $entityType, ?string $entityId, ?string $note = null): void
    {
        AuditLog::query()->create([
            'actorAdminId' => $actorAdminId,
            'action' => $action,
            'entityType' => $entityType,
            'entityId' => $entityId,
            'note' => $note,
        ]);
    }
}
