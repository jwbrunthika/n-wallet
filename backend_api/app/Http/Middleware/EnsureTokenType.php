<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureTokenType
{
    public function handle(Request $request, Closure $next, string $type): Response
    {
        $user = $request->user();
        $tokenType = null;

        try {
            $payload = auth()->payload();
            $tokenType = $payload->get('tokenType') ?? $payload->get('token_type');
        } catch (\Throwable) {
            $tokenType = null;
        }

        if (! $user || $tokenType !== $type) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'UNAUTHORIZED_TOKEN_TYPE',
                    'message' => 'Token type does not match endpoint requirements.',
                    'details' => null,
                ],
            ], 401);
        }

        return $next($request);
    }
}
