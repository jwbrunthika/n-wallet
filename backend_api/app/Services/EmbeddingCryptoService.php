<?php

namespace App\Services;

use Illuminate\Support\Facades\Crypt;

class EmbeddingCryptoService
{
    public function encryptVector(array $vector): array
    {
        $serialized = json_encode($vector, JSON_THROW_ON_ERROR);
        $encrypted = Crypt::encryptString($serialized);

        return [
            'encryptedVector' => base64_encode($encrypted),
            'algo' => 'laravel_crypt_aes_256_cbc_base64',
        ];
    }

    public function decryptVector(string $encryptedVector): array
    {
        $decoded = base64_decode($encryptedVector, true);
        $serialized = Crypt::decryptString((string) $decoded);

        return array_map('floatval', json_decode($serialized, true, 512, JSON_THROW_ON_ERROR));
    }
}
