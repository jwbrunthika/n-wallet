<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\AuditLogService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class AdminFileController extends ApiController
{
    public function __construct(private readonly AuditLogService $auditLogService)
    {
    }

    public function showEnrollmentImage(Request $request, string $email, string $filename)
    {
        $safeEmail = urldecode($email);
        $safeFilename = basename(urldecode($filename));
        $path = 'enrollments/'.$safeEmail.'/'.$safeFilename;

        if (! Storage::disk('local')->exists($path)) {
            return $this->error('FILE_NOT_FOUND', 'Enrollment image not found.', null, 404);
        }

        $this->auditLogService->log(
            (string) $request->user()->_id,
            'view_enrollment_image_file',
            'file',
            $path,
            'Admin viewed enrollment image file'
        );

        return Storage::disk('local')->response($path);
    }
}
