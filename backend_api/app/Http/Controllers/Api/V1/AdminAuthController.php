<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Admin;
use App\Services\AuditLogService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AdminAuthController extends ApiController
{
    public function __construct(private readonly AuditLogService $auditLogService)
    {
    }

    public function login(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $payload = $request->validate([
                'email' => ['required', 'email'],
                'password' => ['required', 'string'],
            ]);

            $admin = Admin::query()->where('email', strtolower((string) $payload['email']))->first();
            if (! $admin || ! Hash::check((string) $payload['password'], (string) $admin->passwordHash)) {
                return $this->error('INVALID_CREDENTIALS', 'Invalid admin credentials.', null, 401);
            }

            if (($admin->token_type ?? null) !== 'admin') {
                $admin->token_type = 'admin';
                $admin->save();
            }

            $token = auth('admin_api')->login($admin);

            $this->auditLogService->log((string) $admin->_id, 'admin_login', 'admin', (string) $admin->_id, 'Admin logged in');

            return $this->success([
                'accessToken' => $token,
                'admin' => [
                    'email' => $admin->email,
                    'role' => $admin->role,
                ],
            ]);
        });
    }

    public function me(Request $request)
    {
        $admin = $request->user();

        return $this->success([
            'email' => $admin->email,
            'role' => $admin->role,
        ]);
    }
}
