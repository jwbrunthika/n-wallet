<?php

namespace App\Services;

use App\Models\OtpRequest;
use App\Support\ApiException;
use Carbon\Carbon;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class OtpService
{
    public function __construct(
        private readonly \App\Services\Otp\MailOtpSender $mailOtpSender,
        private readonly \App\Services\Otp\DevLogOtpSender $devLogOtpSender,
    ) {
    }

    public function requestOtp(string $email): array
    {
        $now = Carbon::now();

        $latest = OtpRequest::query()
            ->where('email', $email)
            ->orderByDesc('created_at')
            ->first();

        if ($latest && $latest->resendAvailableAt && $now->lt($latest->resendAvailableAt)) {
            $waitSeconds = $latest->resendAvailableAt->diffInSeconds($now);
            throw new ApiException(
                'OTP_RESEND_THROTTLED',
                'Please wait before requesting another OTP.',
                429,
                ['retryAfterSec' => $waitSeconds]
            );
        }

        $otp = (string) random_int(100000, 999999);
        $otpRequestId = (string) Str::uuid();
        $expirySec = (int) env('OTP_EXPIRY_SECONDS', 300);
        $cooldownSec = (int) env('OTP_RESEND_COOLDOWN_SECONDS', 60);
        $maxAttempts = (int) env('OTP_MAX_ATTEMPTS', 5);

        OtpRequest::query()->create([
            'otpRequestId' => $otpRequestId,
            'email' => $email,
            'otpHash' => Hash::make($otp),
            'expiresAt' => $now->copy()->addSeconds($expirySec),
            'resendAvailableAt' => $now->copy()->addSeconds($cooldownSec),
            'attemptsLeft' => $maxAttempts,
            'verifiedAt' => null,
        ]);

        // OTP delivery: for dev/demo we can log OTP to backend logs when OTP_DEV_MODE=true.
        if (filter_var(env('OTP_DEV_MODE', false), FILTER_VALIDATE_BOOL)) {
            $this->devLogOtpSender->send($email, $otp);
        } else {
            try {
                $this->mailOtpSender->send($email, $otp);
            } catch (\Throwable $exception) {
                Log::warning('OTP SMTP send failed, falling back to DEV log mode.', [
                    'email' => $email,
                    'exceptionClass' => $exception::class,
                    'exceptionMessage' => $exception->getMessage(),
                ]);

                // If SMTP is unavailable in demo environments, fallback to DEV log mode.
                $this->devLogOtpSender->send($email, $otp);
            }
        }

        return [
            'otpRequestId' => $otpRequestId,
            'expiresInSec' => $expirySec,
        ];
    }

    public function verifyOtp(string $otpRequestId, string $otp): string
    {
        $otpRequest = OtpRequest::query()->where('otpRequestId', $otpRequestId)->first();

        if (! $otpRequest) {
            throw new ApiException('OTP_REQUEST_NOT_FOUND', 'OTP request not found.', 404);
        }

        if ($otpRequest->verifiedAt) {
            throw new ApiException('OTP_ALREADY_USED', 'OTP request is already verified.', 422);
        }

        if (Carbon::now()->gt($otpRequest->expiresAt)) {
            throw new ApiException('OTP_EXPIRED', 'OTP has expired.', 422);
        }

        if ((int) $otpRequest->attemptsLeft <= 0) {
            throw new ApiException('OTP_ATTEMPTS_EXCEEDED', 'Maximum OTP attempts exceeded.', 422);
        }

        if (! Hash::check($otp, $otpRequest->otpHash)) {
            $otpRequest->attemptsLeft = max(0, ((int) $otpRequest->attemptsLeft) - 1);
            $otpRequest->save();

            throw new ApiException(
                'OTP_INVALID',
                'Invalid OTP code.',
                422,
                ['attemptsLeft' => (int) $otpRequest->attemptsLeft]
            );
        }

        $otpRequest->verifiedAt = Carbon::now();
        $otpRequest->save();

        return (string) $otpRequest->email;
    }
}
