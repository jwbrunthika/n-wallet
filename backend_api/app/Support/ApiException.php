<?php

namespace App\Support;

use Exception;

class ApiException extends Exception
{
    public function __construct(
        public readonly string $apiCode,
        public readonly string $apiMessage,
        public readonly int $status = 422,
        public readonly mixed $details = null,
    ) {
        parent::__construct($apiMessage, $status);
    }
}
