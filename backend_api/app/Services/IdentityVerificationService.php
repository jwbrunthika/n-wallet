<?php

namespace App\Services;

use App\Models\AppSetting;
use App\Models\Student;
use App\Services\Face\FaceEmbeddingClient;
use App\Support\ApiException;
use Illuminate\Http\UploadedFile;

class IdentityVerificationService
{
    public function __construct(
        private readonly FaceEmbeddingClient $faceEmbeddingClient,
        private readonly EmbeddingCryptoService $embeddingCryptoService,
    ) {
    }

    /**
     * @param array<int, UploadedFile> $faceFrames
     * @return array{verified:bool,faceScore:float,threshold:float}
     */
    public function verify(Student $student, array $faceFrames): array
    {
        if ($student->enrollmentStatus !== Student::STATUS_ENROLLED || ! isset($student->faceTemplate['encryptedVector'])) {
            throw new ApiException(
                'NOT_ENROLLED',
                'Face verification is unavailable until enrollment is completed.',
                422
            );
        }

        $setting = AppSetting::query()->where('key', 'global')->first();
        $faceThreshold = (float) ($setting->faceMatchThreshold ?? env('FACE_MATCH_THRESHOLD', 0.55));
        $bestFaceScore = $this->bestFaceScore($student, $faceFrames);

        if ($bestFaceScore < $faceThreshold) {
            throw new ApiException(
                'FACE_VERIFY_FAILED',
                'Face verification failed. Please try again in better lighting.',
                422,
                [
                    'faceScore' => $bestFaceScore,
                    'threshold' => $faceThreshold,
                ]
            );
        }

        return [
            'verified' => true,
            'faceScore' => $bestFaceScore,
            'threshold' => $faceThreshold,
        ];
    }

    /**
     * @param array<int, UploadedFile> $faceFrames
     */
    public function bestFaceScore(Student $student, array $faceFrames): float
    {
        if (count($faceFrames) < 1 || count($faceFrames) > 3) {
            throw new ApiException('INVALID_FACE_FRAMES', 'Face frames must contain 1 to 3 images.', 422);
        }

        $template = $this->embeddingCryptoService->decryptVector((string) $student->faceTemplate['encryptedVector']);

        $best = -1.0;

        foreach ($faceFrames as $frame) {
            if (! $frame instanceof UploadedFile) {
                throw new ApiException('INVALID_FACE_FRAME', 'Face frame payload is invalid.', 422);
            }

            $faceData = $this->faceEmbeddingClient->fromImagePath($frame->getRealPath(), $frame->getClientOriginalName() ?: 'frame.jpg');
            $score = $this->cosineSimilarity($template, $faceData['embedding']);
            $best = max($best, $score);
        }

        return max($best, 0.0);
    }

    /**
     * @param array<int, float> $left
     * @param array<int, float> $right
     */
    private function cosineSimilarity(array $left, array $right): float
    {
        $dot = 0.0;
        $leftNorm = 0.0;
        $rightNorm = 0.0;

        for ($i = 0; $i < 512; $i++) {
            $l = (float) ($left[$i] ?? 0.0);
            $r = (float) ($right[$i] ?? 0.0);
            $dot += $l * $r;
            $leftNorm += $l * $l;
            $rightNorm += $r * $r;
        }

        if ($leftNorm <= 0 || $rightNorm <= 0) {
            return 0.0;
        }

        return $dot / (sqrt($leftNorm) * sqrt($rightNorm));
    }
}
