<?php

use Illuminate\Database\Migrations\Migration;

return new class extends Migration
{
    public function up(): void
    {
        // N Wallet uses MongoDB collections and does not create SQL user tables.
    }

    public function down(): void
    {
        // No-op.
    }
};
