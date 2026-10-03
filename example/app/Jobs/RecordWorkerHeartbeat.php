<?php

namespace App\Jobs;

use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Cache;

/**
 * Queued by the scheduler every minute, so the status page shows that both
 * the scheduler and the queue worker are running.
 */
class RecordWorkerHeartbeat implements ShouldQueue
{
    use Queueable;

    public function handle(): void
    {
        Cache::forever('heartbeat.worker', now()->toIso8601String());
    }
}
