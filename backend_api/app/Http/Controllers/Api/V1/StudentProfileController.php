<?php

namespace App\Http\Controllers\Api\V1;

use Illuminate\Http\Request;

class StudentProfileController extends ApiController
{
    public function me(Request $request)
    {
        $student = $request->user();

        return $this->success([
            'email' => $student->email,
            'name' => $student->name,
            'enrollmentStatus' => $student->enrollmentStatus,
            'courseCode' => $student->courseCode,
            'batch' => $student->batch,
            'studyMode' => $student->studyMode,
        ]);
    }
}
