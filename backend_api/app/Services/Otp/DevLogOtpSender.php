<?php

namespace App\Services\Otp;

use Illuminate\Support\Facades\Log;

class DevLogOtpSender implements OtpSender
{
    public function send(string $email, string $otp): void
    {
        Log::info('[OTP_DEV_MODE] Student OTP generated', [
            'email' => $email,
            'otp' => $otp,
        ]);
    }
}
