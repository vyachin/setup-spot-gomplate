<?php

declare(strict_types=1);

$release = trim((string) @file_get_contents(__DIR__ . '/REVISION'));
if ($release === '') {
    $release = 'dev';
}

header('Content-Type: text/html; charset=utf-8');

?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Hello, World!</title>
    <style>
        :root { color-scheme: light dark; }
        body {
            align-items: center;
            display: flex;
            font-family: ui-sans-serif, system-ui, sans-serif;
            justify-content: center;
            margin: 0;
            min-height: 100vh;
        }
        main { text-align: center; }
        h1 { font-size: clamp(2.5rem, 10vw, 5rem); margin: 0 0 1rem; }
        code { font-size: 1rem; opacity: .75; }
    </style>
</head>
<body>
<main>
    <h1>Hello, World!</h1>
    <p>Deployed with <a href="https://github.com/umputun/spot">spot</a> and
        <a href="https://github.com/hairyhenderson/gomplate">gomplate</a>.</p>
    <p>Release: <code><?= htmlspecialchars($release, ENT_QUOTES, 'UTF-8') ?></code></p>
</main>
</body>
</html>
