<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Queue\SerializesModels;

class StudentOtpMail extends Mailable
{
    use Queueable;
    use SerializesModels;

    public function __construct(public readonly string $otp)
    {
    }

    public function build(): self
    {
        return $this
            ->subject('N Wallet OTP Code')
            ->text('mail.student_otp_plain', ['otp' => $this->otp]);
    }
}
