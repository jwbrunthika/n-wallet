<?php

use Illuminate\Database\Migrations\Migration;

return new class extends Migration
{
    public function up(): void
    {
        // N Wallet uses MongoDB and in-memory cache for student project simplicity.
    }

    public function down(): void
    {
        // No-op.
    }
};
