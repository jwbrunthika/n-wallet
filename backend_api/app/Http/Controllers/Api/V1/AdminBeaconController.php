<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Beacon;
use App\Services\AuditLogService;
use Illuminate\Http\Request;

class AdminBeaconController extends ApiController
{
    public function __construct(private readonly AuditLogService $auditLogService)
    {
    }

    public function index()
    {
        $beacons = Beacon::query()->orderBy('uuid')->get()->map(fn (Beacon $beacon): array => [
            'id' => (string) $beacon->_id,
            'uuid' => $beacon->uuid,
            'major' => (int) $beacon->major,
            'minor' => (int) $beacon->minor,
            'hallId' => $beacon->hallId,
            'enabled' => (bool) $beacon->enabled,
        ])->values();

        return $this->success($beacons);
    }

    public function store(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $payload = $request->validate([
                'uuid' => ['required', 'string', 'max:64'],
                'major' => ['required', 'integer', 'min:0'],
                'minor' => ['required', 'integer', 'min:0'],
                'hallId' => ['required', 'string'],
                'enabled' => ['nullable', 'boolean'],
            ]);

            $beacon = Beacon::query()->create([
                'uuid' => strtolower((string) $payload['uuid']),
                'major' => (int) $payload['major'],
                'minor' => (int) $payload['minor'],
                'hallId' => (string) $payload['hallId'],
                'enabled' => (bool) ($payload['enabled'] ?? true),
            ]);

            $adminId = (string) $request->user()->_id;
            $this->auditLogService->log($adminId, 'beacon_create', 'beacon', (string) $beacon->_id, 'Beacon mapping created');

            return $this->success(['id' => (string) $beacon->_id], 201);
        });
    }

    public function show(string $id)
    {
        $beacon = Beacon::query()->find($id);
        if (! $beacon) {
            return $this->error('BEACON_NOT_FOUND', 'Beacon not found.', null, 404);
        }

        return $this->success([
            'id' => (string) $beacon->_id,
            'uuid' => $beacon->uuid,
            'major' => (int) $beacon->major,
            'minor' => (int) $beacon->minor,
            'hallId' => $beacon->hallId,
            'enabled' => (bool) $beacon->enabled,
        ]);
    }

    public function update(Request $request, string $id)
    {
        return $this->guarded(function () use ($request, $id) {
            $beacon = Beacon::query()->find($id);
            if (! $beacon) {
                return $this->error('BEACON_NOT_FOUND', 'Beacon not found.', null, 404);
            }

            $payload = $request->validate([
                'uuid' => ['required', 'string', 'max:64'],
                'major' => ['required', 'integer', 'min:0'],
                'minor' => ['required', 'integer', 'min:0'],
                'hallId' => ['required', 'string'],
                'enabled' => ['required', 'boolean'],
            ]);

            $beacon->uuid = strtolower((string) $payload['uuid']);
            $beacon->major = (int) $payload['major'];
            $beacon->minor = (int) $payload['minor'];
            $beacon->hallId = (string) $payload['hallId'];
            $beacon->enabled = (bool) $payload['enabled'];
            $beacon->save();

            $adminId = (string) $request->user()->_id;
            $this->auditLogService->log($adminId, 'beacon_update', 'beacon', (string) $beacon->_id, 'Beacon mapping updated');

            return $this->success(['id' => (string) $beacon->_id]);
        });
    }

    public function destroy(Request $request, string $id)
    {
        $beacon = Beacon::query()->find($id);
        if (! $beacon) {
            return $this->error('BEACON_NOT_FOUND', 'Beacon not found.', null, 404);
        }

        $beaconId = (string) $beacon->_id;
        $beacon->delete();

        $adminId = (string) $request->user()->_id;
        $this->auditLogService->log($adminId, 'beacon_delete', 'beacon', $beaconId, 'Beacon mapping deleted');

        return $this->success(['deleted' => true]);
    }
}
