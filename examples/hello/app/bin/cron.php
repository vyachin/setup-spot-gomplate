#!/usr/bin/env php
<?php

declare(strict_types=1);

// Runs from cron: /usr/bin/php <release>/bin/cron.php >> <shared>/log/cron.log
$release = trim((string) @file_get_contents(__DIR__ . '/../REVISION'));
if ($release === '') {
    $release = 'dev';
}

printf("[%s] hello-cron tick, release=%s\n", gmdate('c'), $release);
