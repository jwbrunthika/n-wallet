<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Student;
use App\Services\IdentityVerificationService;
use Illuminate\Http\Request;

class StudentIdentityController extends ApiController
{
    public function __construct(private readonly IdentityVerificationService $identityVerificationService)
    {
    }

    public function verify(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $request->validate([
                'faceFrames' => ['required', 'array', 'min:1', 'max:3'],
                'faceFrames.*' => ['required', 'image', 'max:5120'],
            ]);

            /** @var Student $student */
            $student = $request->user();

            $result = $this->identityVerificationService->verify(
                $student,
                $request->file('faceFrames', [])
            );

            return $this->success($result);
        });
    }
}
