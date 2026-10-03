<?php

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

/**
 * Check each part of the setup. A failed check is reported, never thrown, so
 * a broken database shows up on the page instead of failing the health check.
 */
$statusChecks = function (): array {
    $check = function (Closure $probe): array {
        try {
            return ['ok' => true, 'detail' => $probe()];
        } catch (Throwable $exception) {
            return ['ok' => false, 'detail' => class_basename($exception).': '.str($exception->getMessage())->limit(120)];
        }
    };

    $heartbeat = function (string $key) use ($check): array {
        $result = $check(fn () => Cache::get("heartbeat.{$key}"));

        if ($result['ok'] && $result['detail'] === null) {
            return ['ok' => false, 'detail' => 'Not yet. It runs every minute.'];
        }

        return $result['ok'] ? ['ok' => true, 'detail' => 'last ran '.now()->parse($result['detail'])->diffForHumans()] : $result;
    };

    return [
        'MySQL' => $check(fn () => 'version '.DB::scalar('select version()').', '.DB::table('migrations')->count().' migrations run'),
        'Redis' => $check(fn () => 'page viewed '.Cache::increment('views').' times'),
        'Scheduler' => $heartbeat('scheduler'),
        'Queue worker' => $heartbeat('worker'),
    ];
};

/**
 * One page that shows each part of the setup working. It always answers 200.
 */
Route::get('/', fn () => abort(500, 'Broken on purpose for the nightly test.'));

Route::get('/working', fn () => view('status', [
    'version' => config('app.version'),
    'checks' => $statusChecks(),
]));

/**
 * The same checks for scripts, such as Lowol's nightly test.
 */
Route::get('/status.json', fn () => [
    'version' => config('app.version'),
    'checks' => $statusChecks(),
]);
