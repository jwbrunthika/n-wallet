<?php

namespace Tests\Unit;

use App\Services\EmbeddingCryptoService;
use Illuminate\Encryption\Encrypter;
use Illuminate\Support\Facades\Crypt;
use Tests\TestCase;

class EmbeddingCryptoServiceTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        $key = str_repeat('a', 32);
        Crypt::swap(new Encrypter($key, 'AES-256-CBC'));
    }

    public function test_encrypt_and_decrypt_roundtrip(): void
    {
        $service = new EmbeddingCryptoService();
        $vector = array_fill(0, 512, 0.1234);

        $encrypted = $service->encryptVector($vector);
        $decrypted = $service->decryptVector($encrypted['encryptedVector']);

        $this->assertCount(512, $decrypted);
        $this->assertEquals($vector[0], $decrypted[0]);
    }
}
