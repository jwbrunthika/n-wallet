<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Student;
use App\Services\OtpService;
use Illuminate\Http\Request;

class StudentAuthController extends ApiController
{
    public function __construct(private readonly OtpService $otpService)
    {
    }

    public function requestOtp(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $payload = $request->validate([
                'email' => ['required', 'email'],
            ]);

            $result = $this->otpService->requestOtp(strtolower((string) $payload['email']));

            return $this->success($result);
        });
    }

    public function verifyOtp(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $payload = $request->validate([
                'otpRequestId' => ['required', 'string'],
                'otp' => ['required', 'digits:6'],
            ]);

            $email = $this->otpService->verifyOtp($payload['otpRequestId'], $payload['otp']);

            $student = Student::query()->firstOrCreate(
                ['email' => $email],
                [
                    'name' => null,
                    'enrollmentStatus' => Student::STATUS_NOT_ENROLLED,
                    'enrollmentImages' => [],
                    'token_type' => 'student',
                    'courseCode' => null,
                    'batch' => null,
                    'studyMode' => null,
                ]
            );

            if (($student->token_type ?? null) !== 'student') {
                $student->token_type = 'student';
                $student->save();
            }

            $token = auth('student_api')->login($student);

            return $this->success([
                'accessToken' => $token,
                'student' => [
                    'email' => $student->email,
                    'enrollmentStatus' => $student->enrollmentStatus,
                    'courseCode' => $student->courseCode,
                    'batch' => $student->batch,
                    'studyMode' => $student->studyMode,
                ],
            ]);
        });
    }
}
