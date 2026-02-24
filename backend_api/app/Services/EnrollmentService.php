<?php

namespace App\Services;

use App\Models\Student;
use App\Services\Face\FaceEmbeddingClient;
use App\Support\ApiException;
use Carbon\Carbon;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

class EnrollmentService
{
    public function __construct(
        private readonly FaceEmbeddingClient $faceEmbeddingClient,
        private readonly EmbeddingCryptoService $embeddingCryptoService,
        private readonly AcademicProfileService $academicProfileService,
    ) {
    }

    /**
     * @param array<int, UploadedFile> $images
     */
    public function enroll(Student $student, array $images): array
    {
        $this->academicProfileService->assertStudentHasAcademicProfile($student);

        if (count($images) !== 3) {
            throw new ApiException('INVALID_ENROLLMENT_IMAGES', 'Exactly 3 enrollment images are required.', 422);
        }

        $savedImages = [];
        $embeddings = [];
        $qualityScores = [];
        $modelVersions = [];

        foreach ($images as $index => $image) {
            if (! $image instanceof UploadedFile) {
                throw new ApiException('INVALID_IMAGE_PAYLOAD', 'Enrollment images payload is invalid.', 422);
            }

            $timestamp = Carbon::now()->format('YmdHisv');
            $extension = $image->getClientOriginalExtension() ?: 'jpg';
            $filename = $timestamp.'_'.$index.'.'.$extension;
            $relativePath = 'enrollments/'.$student->email.'/'.$filename;

            $realPath = $image->getRealPath();
            if (! is_string($realPath) || $realPath === '' || ! is_readable($realPath)) {
                throw new ApiException('ENROLLMENT_IMAGE_READ_ERROR', 'Uploaded image could not be read from temporary storage.', 422);
            }

            $imageBytes = file_get_contents($realPath);
            if ($imageBytes === false) {
                throw new ApiException('ENROLLMENT_IMAGE_READ_ERROR', 'Failed to read uploaded image bytes.', 422);
            }

            try {
                Storage::disk('local')->put($relativePath, $imageBytes);
            } catch (\Throwable $exception) {
                throw new ApiException(
                    'ENROLLMENT_IMAGE_STORE_ERROR',
                    'Failed to store enrollment image on server.',
                    500,
                    $exception->getMessage()
                );
            }

            $absolutePath = storage_path('app/'.$relativePath);

            $faceData = $this->faceEmbeddingClient->fromImagePath($absolutePath, $filename);
            $embeddings[] = $faceData['embedding'];
            $qualityScores[] = $faceData['qualityScore'];
            $modelVersions[] = $faceData['modelVersion'];

            $savedImages[] = [
                'path' => $relativePath,
                'qualityScore' => $faceData['qualityScore'],
                'createdAt' => Carbon::now()->toIso8601String(),
            ];
        }

        $avgEmbedding = $this->averageEmbedding($embeddings);
        $normalizedEmbedding = $this->normalizeEmbedding($avgEmbedding);

        // Face template encryption: vector is serialized then encrypted with Laravel Crypt.
        // We store base64(encryptedPayload) to keep Mongo document JSON-safe and readable.
        $encrypted = $this->embeddingCryptoService->encryptVector($normalizedEmbedding);

        $student->faceTemplate = [
            'encryptedVector' => $encrypted['encryptedVector'],
            'algo' => $encrypted['algo'],
            'modelVersion' => $modelVersions[0] ?? 'arcface-onnx-1.0',
            'createdAt' => Carbon::now()->toIso8601String(),
        ];
        $student->enrollmentImages = $savedImages;
        $student->enrollmentStatus = Student::STATUS_ENROLLED;
        $student->save();

        return [
            'enrollmentStatus' => $student->enrollmentStatus,
            'modelVersion' => $student->faceTemplate['modelVersion'],
            'qualitySummary' => [
                'min' => min($qualityScores),
                'max' => max($qualityScores),
                'avg' => array_sum($qualityScores) / max(1, count($qualityScores)),
            ],
        ];
    }

    /**
     * @param array<int, array<int, float>> $embeddings
     * @return array<int, float>
     */
    private function averageEmbedding(array $embeddings): array
    {
        $count = count($embeddings);
        if ($count === 0) {
            throw new ApiException('EMBEDDING_EMPTY', 'No embeddings generated for enrollment.', 422);
        }

        $avg = array_fill(0, 512, 0.0);

        foreach ($embeddings as $embedding) {
            if (count($embedding) !== 512) {
                throw new ApiException('EMBEDDING_SIZE_INVALID', 'Embedding size mismatch.', 422);
            }

            foreach ($embedding as $i => $value) {
                $avg[$i] += (float) $value;
            }
        }

        foreach ($avg as $i => $value) {
            $avg[$i] = $value / $count;
        }

        return $avg;
    }

    /**
     * @param array<int, float> $vector
     * @return array<int, float>
     */
    private function normalizeEmbedding(array $vector): array
    {
        $norm = 0.0;

        foreach ($vector as $value) {
            $norm += $value * $value;
        }

        $norm = sqrt($norm);
        if ($norm <= 0) {
            throw new ApiException('EMBEDDING_NORMALIZATION_FAILED', 'Embedding norm is zero.', 422);
        }

        return array_map(static fn (float $value): float => $value / $norm, $vector);
    }
}
