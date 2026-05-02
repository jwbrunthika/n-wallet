<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Beacon;
use App\Services\AuditLogService;
use App\Support\ApiException;
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

            $uuid = strtolower((string) $payload['uuid']);
            $major = (int) $payload['major'];
            $minor = (int) $payload['minor'];

            if ($this->beaconIdentityExists($uuid, $major, $minor)) {
                return $this->duplicateBeaconIdentityError();
            }

            try {
                $beacon = Beacon::query()->create([
                    'uuid' => $uuid,
                    'major' => $major,
                    'minor' => $minor,
                    'hallId' => (string) $payload['hallId'],
                    'enabled' => (bool) ($payload['enabled'] ?? true),
                ]);
            } catch (\Throwable $exception) {
                $this->throwDuplicateBeaconIdentityIfNeeded($exception);

                throw $exception;
            }

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

            $uuid = strtolower((string) $payload['uuid']);
            $major = (int) $payload['major'];
            $minor = (int) $payload['minor'];

            if ($this->beaconIdentityExists($uuid, $major, $minor, $id)) {
                return $this->duplicateBeaconIdentityError();
            }

            $beacon->uuid = $uuid;
            $beacon->major = $major;
            $beacon->minor = $minor;
            $beacon->hallId = (string) $payload['hallId'];
            $beacon->enabled = (bool) $payload['enabled'];
            try {
                $beacon->save();
            } catch (\Throwable $exception) {
                $this->throwDuplicateBeaconIdentityIfNeeded($exception);

                throw $exception;
            }

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

    private function beaconIdentityExists(string $uuid, int $major, int $minor, ?string $exceptId = null): bool
    {
        $existing = Beacon::query()
            ->where('uuid', $uuid)
            ->where('major', $major)
            ->where('minor', $minor)
            ->first();

        if (! $existing) {
            return false;
        }

        return $exceptId === null || (string) $existing->_id !== $exceptId;
    }

    private function duplicateBeaconIdentityError()
    {
        return $this->error(
            'BEACON_IDENTITY_EXISTS',
            'A beacon with this UUID, major, and minor already exists.',
            null,
            422
        );
    }

    private function throwDuplicateBeaconIdentityIfNeeded(\Throwable $exception): void
    {
        $message = $exception->getMessage();

        if (
            str_contains($message, 'E11000') &&
            (
                str_contains($message, 'uuid_1_major_1_minor_1') ||
                (str_contains($message, 'uuid') && str_contains($message, 'major') && str_contains($message, 'minor'))
            )
        ) {
            throw new ApiException(
                'BEACON_IDENTITY_EXISTS',
                'A beacon with this UUID, major, and minor already exists.',
                422
            );
        }
    }
}
