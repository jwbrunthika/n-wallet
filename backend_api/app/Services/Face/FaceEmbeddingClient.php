<?php

namespace App\Services\Face;

use App\Support\ApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

class FaceEmbeddingClient
{
    public function fromImagePath(string $path, string $filename = 'image.jpg'): array
    {
        $url = rtrim((string) config('services.face_service.url'), '/').'/embedding/from-image-bytes';

        if (! is_file($path) || ! is_readable($path)) {
            throw new ApiException(
                'FACE_IMAGE_READ_ERROR',
                'Server could not read the uploaded enrollment image.',
                422,
                ['path' => $path]
            );
        }

        $imageBytes = file_get_contents($path);
        if ($imageBytes === false) {
            throw new ApiException(
                'FACE_IMAGE_READ_ERROR',
                'Server failed to read uploaded enrollment image bytes.',
                422
            );
        }

        try {
            $response = Http::timeout(60)
                ->attach('image', $imageBytes, $filename)
                ->post($url);
        } catch (ConnectionException $exception) {
            throw new ApiException(
                'FACE_SERVICE_UNREACHABLE',
                'Face service is unreachable.',
                502,
                $exception->getMessage()
            );
        } catch (\Throwable $exception) {
            throw new ApiException(
                'FACE_SERVICE_REQUEST_FAILED',
                'Face service request failed before receiving a response.',
                502,
                $exception->getMessage()
            );
        }

        if (! $response->successful()) {
            $details = $response->json();
            if (! is_array($details)) {
                $details = [
                    'status' => $response->status(),
                    'body' => substr((string) $response->body(), 0, 500),
                ];
            }

            // Map known face-quality issues to 422 so the mobile app can show
            // a retry message instead of treating it as server failure.
            $detailText = strtolower((string) ($details['detail'] ?? ''));
            if ($response->status() === 422) {
                if (str_contains($detailText, 'no face')) {
                    throw new ApiException(
                        'FACE_NOT_DETECTED',
                        'No face detected. Retake photos with good lighting and keep your full face in frame.',
                        422,
                        $details
                    );
                }

                throw new ApiException(
                    'FACE_IMAGE_INVALID',
                    'Invalid face image. Retake the photo and try again.',
                    422,
                    $details
                );
            }

            throw new ApiException(
                'FACE_SERVICE_ERROR',
                'Face service request failed.',
                502,
                $details
            );
        }

        $payload = $response->json();

        if (! is_array($payload) || ! isset($payload['embedding']) || ! is_array($payload['embedding']) || count($payload['embedding']) !== 512) {
            throw new ApiException('FACE_SERVICE_INVALID_RESPONSE', 'Face service returned invalid embedding.', 502);
        }

        return [
            'embedding' => array_map('floatval', $payload['embedding']),
            'qualityScore' => (float) ($payload['qualityScore'] ?? 0),
            'modelVersion' => (string) ($payload['modelVersion'] ?? 'arcface-onnx-1.0'),
        ];
    }
}
