<?php

namespace App\Services\Otp;

interface OtpSender
{
    public function send(string $email, string $otp): void;
}
