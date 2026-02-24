<?php

namespace Database\Seeders;

use App\Models\Admin;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class AdminSeeder extends Seeder
{
    public function run(): void
    {
        Admin::query()->updateOrCreate(
            ['email' => 'nwallet.2002@gmail.com'],
            [
                'passwordHash' => Hash::make('Nodecmb@2k26'),
                'role' => 'SUPER_ADMIN',
                'token_type' => 'admin',
            ]
        );
    }
}
