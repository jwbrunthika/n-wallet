<?php

namespace App\Http\Controllers\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class StudentSupportController extends ApiController
{
    public function reportIssue(Request $request)
    {
        $payload = $request->validate([
            'message' => ['required', 'string', 'max:1000'],
        ]);

        Log::warning('Student support report', [
            'studentEmail' => $request->user()->email,
            'message' => $payload['message'],
        ]);

        return $this->success(['reported' => true]);
    }
}
