<?php

use App\Http\Controllers\Api\V1\AdminAttendanceController;
use App\Http\Controllers\Api\V1\AdminAuthController;
use App\Http\Controllers\Api\V1\AdminBeaconController;
use App\Http\Controllers\Api\V1\AdminCourseController;
use App\Http\Controllers\Api\V1\AdminFileController;
use App\Http\Controllers\Api\V1\AdminHallController;
use App\Http\Controllers\Api\V1\AdminModuleController;
use App\Http\Controllers\Api\V1\AdminSessionController;
use App\Http\Controllers\Api\V1\AdminSettingsController;
use App\Http\Controllers\Api\V1\AdminStudentController;
use App\Http\Controllers\Api\V1\HealthController;
use App\Http\Controllers\Api\V1\StudentAttendanceController;
use App\Http\Controllers\Api\V1\StudentAuthController;
use App\Http\Controllers\Api\V1\StudentEnrollmentController;
use App\Http\Controllers\Api\V1\StudentIdentityController;
use App\Http\Controllers\Api\V1\StudentProfileController;
use App\Http\Controllers\Api\V1\StudentSessionController;
use App\Http\Controllers\Api\V1\TimetableImportController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function (): void {
    Route::get('/health', [HealthController::class, 'index']);

    Route::prefix('auth')->group(function (): void {
        Route::prefix('student')->group(function (): void {
            Route::post('/request-otp', [StudentAuthController::class, 'requestOtp']);
            Route::post('/verify-otp', [StudentAuthController::class, 'verifyOtp']);
        });

        Route::post('/admin/login', [AdminAuthController::class, 'login']);
    });

    Route::middleware(['auth:student_api', 'token.type:student'])->prefix('student')->group(function (): void {
        Route::get('/me', [StudentProfileController::class, 'me']);
        Route::post('/identity/verify', [StudentIdentityController::class, 'verify']);

        Route::prefix('enrollment')->group(function (): void {
            Route::post('/upload', [StudentEnrollmentController::class, 'upload']);
            Route::get('/status', [StudentEnrollmentController::class, 'status']);
        });

        Route::prefix('sessions')->group(function (): void {
            Route::get('/today', [StudentSessionController::class, 'today']);
            Route::get('/{sessionId}', [StudentSessionController::class, 'show']);
        });

        Route::prefix('attendance')->group(function (): void {
            Route::post('/submit', [StudentAttendanceController::class, 'submit']);
            Route::get('/history', [StudentAttendanceController::class, 'history']);
        });
    });

    Route::middleware(['auth:admin_api', 'token.type:admin'])->prefix('admin')->group(function (): void {
        Route::get('/me', [AdminAuthController::class, 'me']);

        Route::apiResource('halls', AdminHallController::class);
        Route::apiResource('beacons', AdminBeaconController::class);
        Route::apiResource('modules', AdminModuleController::class);
        Route::apiResource('courses', AdminCourseController::class);

        Route::post('/timetable/import', [TimetableImportController::class, 'import']);
        Route::get('/sessions', [AdminSessionController::class, 'index']);

        Route::get('/students', [AdminStudentController::class, 'index']);
        Route::get('/students/{email}', [AdminStudentController::class, 'show']);
        Route::patch('/students/{email}', [AdminStudentController::class, 'update']);
        Route::delete('/students/{email}', [AdminStudentController::class, 'destroy']);
        Route::patch('/students/{email}/academic-profile', [AdminStudentController::class, 'updateAcademicProfile']);
        Route::post('/students/{email}/reset-enrollment', [AdminStudentController::class, 'resetEnrollment']);
        Route::get('/students/{email}/enrollment-images', [AdminStudentController::class, 'enrollmentImages']);

        Route::get('/attendance/logs', [AdminAttendanceController::class, 'logs']);
        Route::get('/attendance/export', [AdminAttendanceController::class, 'export']);

        Route::get('/settings', [AdminSettingsController::class, 'show']);
        Route::patch('/settings', [AdminSettingsController::class, 'update']);

        Route::get('/files/enrollments/{email}/{filename}', [AdminFileController::class, 'showEnrollmentImage'])
            ->where('filename', '.*');
    });
});
