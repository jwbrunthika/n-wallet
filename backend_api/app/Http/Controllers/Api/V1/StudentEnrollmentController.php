<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Student;
use App\Services\EnrollmentService;
use App\Support\ApiException;
use Illuminate\Http\Request;

class StudentEnrollmentController extends ApiController
{
    public function __construct(private readonly EnrollmentService $enrollmentService)
    {
    }

    public function upload(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $request->validate([
                'images' => ['required', 'array', 'size:3'],
                'images.*' => ['required', 'image', 'max:5120'],
            ]);

            /** @var Student $student */
            $student = $request->user();

            try {
                $result = $this->enrollmentService->enroll($student, $request->file('images', []));
            } catch (\Throwable $exception) {
                $shouldMarkFailed = ! ($exception instanceof ApiException
                    && $exception->apiCode === 'ACADEMIC_PROFILE_REQUIRED');

                if ($shouldMarkFailed) {
                    $student->enrollmentStatus = Student::STATUS_FAILED;
                    try {
                        $student->save();
                    } catch (\Throwable $saveException) {
                        report($saveException);
                    }
                }
                throw $exception;
            }

            return $this->success($result);
        });
    }

    public function status(Request $request)
    {
        /** @var Student $student */
        $student = $request->user();

        return $this->success([
            'enrollmentStatus' => $student->enrollmentStatus,
            'courseCode' => $student->courseCode,
            'batch' => $student->batch,
            'studyMode' => $student->studyMode,
            'faceTemplate' => [
                'modelVersion' => $student->faceTemplate['modelVersion'] ?? null,
                'createdAt' => $student->faceTemplate['createdAt'] ?? null,
            ],
        ]);
    }
}
