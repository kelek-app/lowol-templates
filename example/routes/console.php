<?php

use App\Jobs\RecordWorkerHeartbeat;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Schedule;

Schedule::call(function () {
    Cache::forever('heartbeat.scheduler', now()->toIso8601String());
    RecordWorkerHeartbeat::dispatch();
})->name('heartbeat')->everyMinute();
