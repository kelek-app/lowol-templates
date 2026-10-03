<?php

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

/**
 * One page that shows each part of the setup working. It always answers 200,
 * so a broken database shows up here instead of failing the health check.
 */
Route::get('/', function () {
    throw new RuntimeException('Broken on purpose, to test that Lowol rolls back.');

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

    return view('status', [
        'version' => config('app.version'),
        'checks' => [
            'MySQL' => $check(fn () => 'version '.DB::scalar('select version()').', '.DB::table('migrations')->count().' migrations run'),
            'Redis' => $check(fn () => 'page viewed '.Cache::increment('views').' times'),
            'Scheduler' => $heartbeat('scheduler'),
            'Queue worker' => $heartbeat('worker'),
        ],
    ]);
});
