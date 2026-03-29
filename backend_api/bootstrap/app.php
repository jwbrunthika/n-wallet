<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use App\Support\ApiException;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Illuminate\Auth\AuthenticationException;
use Symfony\Component\HttpFoundation\Response;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/api/v1/healthz',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'token.type' => \App\Http\Middleware\EnsureTokenType::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(function (ApiException $exception): Response {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => $exception->apiCode,
                    'message' => $exception->apiMessage,
                    'details' => $exception->details,
                ],
            ], $exception->status);
        });

        $exceptions->render(function (ValidationException $exception): Response {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'VALIDATION_ERROR',
                    'message' => 'Validation failed.',
                    'details' => $exception->errors(),
                ],
            ], 422);
        });

        $exceptions->render(function (AuthenticationException $exception): Response {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'UNAUTHORIZED',
                    'message' => 'Unauthorized.',
                    'details' => null,
                ],
            ], 401);
        });

        $exceptions->render(function (HttpExceptionInterface $exception): Response {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'HTTP_ERROR',
                    'message' => $exception->getMessage() ?: 'HTTP error.',
                    'details' => null,
                ],
            ], $exception->getStatusCode());
        });
    })->create();
