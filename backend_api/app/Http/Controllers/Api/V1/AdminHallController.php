<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\LectureHall;
use Illuminate\Http\Request;

class AdminHallController extends ApiController
{
    public function index()
    {
        $halls = LectureHall::query()->orderBy('name')->get()->map(fn (LectureHall $hall): array => [
            'id' => (string) $hall->_id,
            'name' => $hall->name,
        ])->values();

        return $this->success($halls);
    }

    public function store(Request $request)
    {
        return $this->guarded(function () use ($request) {
            $payload = $request->validate([
                'name' => ['required', 'string', 'max:255'],
            ]);

            $hall = LectureHall::query()->create(['name' => $payload['name']]);

            return $this->success(['id' => (string) $hall->_id, 'name' => $hall->name], 201);
        });
    }

    public function show(string $id)
    {
        $hall = LectureHall::query()->find($id);
        if (! $hall) {
            return $this->error('HALL_NOT_FOUND', 'Hall not found.', null, 404);
        }

        return $this->success(['id' => (string) $hall->_id, 'name' => $hall->name]);
    }

    public function update(Request $request, string $id)
    {
        return $this->guarded(function () use ($request, $id) {
            $hall = LectureHall::query()->find($id);
            if (! $hall) {
                return $this->error('HALL_NOT_FOUND', 'Hall not found.', null, 404);
            }

            $payload = $request->validate([
                'name' => ['required', 'string', 'max:255'],
            ]);

            $hall->name = $payload['name'];
            $hall->save();

            return $this->success(['id' => (string) $hall->_id, 'name' => $hall->name]);
        });
    }

    public function destroy(string $id)
    {
        $hall = LectureHall::query()->find($id);
        if (! $hall) {
            return $this->error('HALL_NOT_FOUND', 'Hall not found.', null, 404);
        }

        $hall->delete();

        return $this->success(['deleted' => true]);
    }
}
