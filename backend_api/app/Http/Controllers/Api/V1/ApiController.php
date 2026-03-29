<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Support\ApiException;
use App\Support\ApiResponse;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

abstract class ApiController extends Controller
{
    use ApiResponse;

    /**
     * @param callable(): JsonResponse $callback
     */
    protected function guarded(callable $callback): JsonResponse
    {
        try {
            return $callback();
        } catch (ValidationException $exception) {
            return $this->error(
                'VALIDATION_ERROR',
                'Validation failed.',
                $exception->errors(),
                422
            );
        } catch (AuthenticationException $exception) {
            return $this->error(
                'UNAUTHORIZED',
                'Unauthorized.',
                null,
                401
            );
        } catch (ApiException $exception) {
            return $this->error(
                $exception->apiCode,
                $exception->apiMessage,
                $exception->details,
                $exception->status
            );
        } catch (HttpExceptionInterface $exception) {
            return $this->error(
                'HTTP_ERROR',
                $exception->getMessage() ?: 'HTTP error.',
                null,
                $exception->getStatusCode()
            );
        } catch (\Throwable $exception) {
            report($exception);

            return $this->error(
                'SERVER_ERROR',
                'Unexpected server error.',
                config('app.debug') ? $exception->getMessage() : null,
                500
            );
        }
    }
}
