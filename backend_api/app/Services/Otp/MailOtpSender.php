<?php

namespace App\Services\Otp;

use App\Mail\StudentOtpMail;
use Illuminate\Support\Facades\Mail;

class MailOtpSender implements OtpSender
{
    public function send(string $email, string $otp): void
    {
        Mail::to($email)->send(new StudentOtpMail($otp));
    }
}
