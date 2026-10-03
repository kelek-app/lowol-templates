<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ config('app.name') }}</title>
    @vite('resources/css/app.css')
</head>
<body class="min-h-screen bg-stone-50 text-stone-900 antialiased">
    <main class="mx-auto max-w-xl px-4 py-16">
        <p class="text-sm text-stone-500">lowol example app</p>
        <h1 class="mt-1 text-2xl font-semibold">{{ config('app.name') }}</h1>
        <p class="mt-1 font-mono text-sm text-stone-600">version {{ $version }}</p>

        <ul class="mt-8 divide-y divide-stone-200 rounded-lg border border-stone-200 bg-white">
            @foreach ($checks as $name => $check)
                <li class="flex items-start gap-3 px-4 py-3">
                    <span @class(['mt-1.5 size-2 shrink-0 rounded-full', 'bg-emerald-500' => $check['ok'], 'bg-red-500' => ! $check['ok']])></span>
                    <div>
                        <p class="font-medium">{{ $name }}</p>
                        <p class="text-sm text-stone-600">{{ $check['detail'] }}</p>
                    </div>
                </li>
            @endforeach
        </ul>
    </main>
</body>
</html>
