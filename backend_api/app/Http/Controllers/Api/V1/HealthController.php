<?php

namespace App\Http\Controllers\Api\V1;

class HealthController extends ApiController
{
    public function index()
    {
        return $this->success([
            'service' => 'n-wallet-api',
            'status' => 'ok',
            'timestamp' => now()->toIso8601String(),
        ]);
    }
}
