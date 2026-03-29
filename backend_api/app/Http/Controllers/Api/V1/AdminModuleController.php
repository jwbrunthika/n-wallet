<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\CourseModule;
use Illuminate\Http\Request;

class AdminModuleController extends ApiController
{
    public function index()
    {
        $modules = CourseModule::query()->orderBy('moduleCode')->get()->map(fn (CourseModule $module): array => [
            'id' => (string) $module->_id,
            'moduleCode' => $module->moduleCode,
            'moduleName' => $module->moduleName,
            'leaderAdminId' => $module->leaderAdminId,
        ])->values();

        return $this->success($modules);
    }

    public function store(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $payload = $request->validate([
                'moduleCode' => ['required', 'string', 'max:32'],
                'moduleName' => ['required', 'string', 'max:255'],
                'leaderAdminId' => ['nullable', 'string'],
            ]);

            $module = CourseModule::query()->create($payload);

            return $this->success(['id' => (string) $module->_id], 201);
        });
    }

    public function show(string $id)
    {
        $module = CourseModule::query()->find($id);
        if (! $module) {
            return $this->error('MODULE_NOT_FOUND', 'Module not found.', null, 404);
        }

        return $this->success([
            'id' => (string) $module->_id,
            'moduleCode' => $module->moduleCode,
            'moduleName' => $module->moduleName,
            'leaderAdminId' => $module->leaderAdminId,
        ]);
    }

    public function update(Request $request, string $id)
    {
        return $this->guarded(function () use ($request, $id) {
            $module = CourseModule::query()->find($id);
            if (! $module) {
                return $this->error('MODULE_NOT_FOUND', 'Module not found.', null, 404);
            }

            $payload = $request->validate([
                'moduleCode' => ['required', 'string', 'max:32'],
                'moduleName' => ['required', 'string', 'max:255'],
                'leaderAdminId' => ['nullable', 'string'],
            ]);

            $module->fill($payload);
            $module->save();

            return $this->success(['id' => (string) $module->_id]);
        });
    }

    public function destroy(string $id)
    {
        $module = CourseModule::query()->find($id);
        if (! $module) {
            return $this->error('MODULE_NOT_FOUND', 'Module not found.', null, 404);
        }

        $module->delete();

        return $this->success(['deleted' => true]);
    }
}
