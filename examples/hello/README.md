# Hello example: публикация PHP-приложения через spot и gomplate

Маленькое приложение `index.php` печатает `Hello, World!` и номер релиза. Деплой показывает
три вещи, ради которых в проекте используются spot и gomplate:

1. **Публикация без простоя.** Новый релиз распаковывается в отдельный каталог, затем
   symlink `current` переключается атомарно. nginx в это время отдаёт старый или новый
   релиз, но не 404/502.
2. **Обновление конфига nginx.** Конфиг рендерится gomplate при каждом деплое, проверяется
   через `nginx -t` и применяется graceful-перезагрузкой. Если health-check не прошёл,
   spot возвращает и код, и конфиг.
3. **Управление задачей крона.** spot идемпотентно заменяет только свой блок в crontab,
   не трогая остальные задачи пользователя.

## Состав

```
examples/hello/
├── app/
│   ├── index.php                  # Hello, World! + REVISION
│   └── bin/cron.php               # задача для cron
├── scripts/
│   ├── build-release.sh           # собирает tar.gz с REVISION
│   └── render.sh                  # gomplate по всем *.tmpl
├── spot/
│   ├── config.yml                 # переменные деплоя
│   ├── inventory.yml.tmpl         # хост/порт/пользователь из окружения
│   ├── nginx-hello.conf.tmpl      # server-блок с root на current
│   └── spot.yml                   # playbook
└── test/
    ├── Dockerfile                 # Debian + nginx + php-fpm + cron + sshd
    ├── entrypoint.sh
    └── sandbox.sh                 # e2e-проверка на одноразовом контейнере
```

Workflow: [`.github/workflows/hello.yml`](../../.github/workflows/hello.yml).
Установщик инструментов: [`action.yml`](../../action.yml).

## Быстрый запуск в Docker

Нужны `docker`, `curl`, `ssh`, `ssh-keygen` и установленные `spot`/`gomplate`.

```bash
# из корня репозитория
SPOT_VERSION=v1.20.1 GOMPLATE_VERSION=v5.3.1 INSTALL_DIR="$HOME/.local/bin" \
  bash ./install.sh
export PATH="$HOME/.local/bin:$PATH"

examples/hello/test/sandbox.sh
```

Скрипт:

- поднимает Debian-контейнер с nginx, php-fpm, cron и sshd (порт SSH публикуется случайно);
- рендерит `inventory.yml` и nginx-конфиг через gomplate;
- делает три деплоя разными версиями;
- во время второго деплоя непрерывно шлёт запросы и проверяет, что не было ни одного отказа;
- проверяет, что `current` указывает на новый релиз, старые релизы подчищаются (остаётся 3);
- проверяет, что в crontab ровно один управляемый блок, он указывает на активный релиз,
  а посторонняя запись `echo keep-me` сохранилась.

Если нужен подробный вывод spot: `SPOT_VERBOSE=1 examples/hello/test/sandbox.sh`.

## Как устроен деплой

`examples/hello/spot/spot.yml`, task `deploy`:

1. Проверяет входные переменные, создаёт `shared/log`.
2. `RELEASE=<UTC timestamp>`, каталог `releases/<RELEASE>`.
3. Загружает и распаковывает архив, линкует shared-каталоги.
4. Локально запускает `gomplate` — рендерит `nginx-hello.conf` с версией релиза.
5. Кладёт конфиг в `/tmp/hello-nginx.conf`, затем под sudo:
   - сохраняет предыдущий `/etc/nginx/sites-enabled/hello.conf` в `/tmp/hello.conf.previous`;
   - устанавливает новый и выполняет `nginx -t`; при ошибке возвращает предыдущий файл.
6. Под sudo: `systemctl reload nginx`, атомарная замена symlink `current` и health-check.
   Health-check ждёт, пока запрос вернёт **и** версию в теле, **и** заголовок
   `X-Hello-Release: <версия>`. Если не дождались — возвращаются symlink и конфиг,
   nginx перезагружается со старым конфигом, деплой падает.
7. Идемпотентно обновляет блок в crontab между маркерами
   `# BEGIN hello-example (managed by spot)` и `# END hello-example (managed by spot)`.
8. Удаляет старые релизы, оставляя три последних.

### Почему нет простоя

- Архив распаковывается в новый каталог, пока старый продолжает обслуживаться.
- `ln -sfn` + `mv -Tf` заменяют symlink одной операцией: пути `current` не существует
  «наполовину».
- nginx получает `SIGHUP` (`systemctl reload`), а не `restart`: старые worker'ы
  дообслуживают текущие запросы, новые принимают новые.
- `fastcgi_param SCRIPT_FILENAME $realpath_root/index.php` важен для PHP opcache:
  он резолвит symlink на каждый запрос, поэтому новый релиз — это новый realpath и
  новый файл в opcache. С `$document_root` opcache может продолжать отдавать старый файл.
- Health-check с версией в теле и заголовке не даёт объявить деплой успешным, пока
  новые worker'ы реально не начали отдавать новый код и конфиг.

### Крон

В crontab добавляется ровно одна строка:

```
# BEGIN hello-example (managed by spot)
17 * * * * /usr/bin/php /var/www/hello/releases/<RELEASE>/bin/cron.php >> /var/www/hello/shared/log/cron.log 2>&1
# END hello-example (managed by spot)
```

При следующем деплое старый блок удаляется по маркерам, новый добавляется. Чужие строки
остаются как есть. Путь к PHP задаётся переменной `PHP_BIN` в `spot/config.yml`.

Запуск вручную:

```bash
sudo -u deploy /usr/bin/php /var/www/hello/current/bin/cron.php
```

## Ручной деплой

На сервере (Debian/Ubuntu) должны быть `nginx`, `php-fpm`, `cron` и пользователь `deploy`
с SSH-ключом. Пример конфигурации sudo для демо (в продакшене ограничьте права):

```bash
echo 'deploy ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/deploy
sudo chmod 0440 /etc/sudoers.d/deploy
```

Переменные окружения:

| Переменная | Пример | Назначение |
| --- | --- | --- |
| `SOURCE` | `/tmp/hello.tar.gz` | архив релиза (локальный путь) |
| `VERSION` | `$GITHUB_SHA` | версия для `REVISION` и `X-Hello-Release` |
| `DEPLOY_HOST` | `203.0.113.10` | сервер |
| `DEPLOY_PORT` | `22` | SSH-порт |
| `DEPLOY_USER` | `deploy` | SSH-пользователь |
| `SERVER_NAME` | `hello.example.com` | `server_name` в nginx |
| `HTTP_PORT` | `80` | порт, который слушает nginx |
| `PHP_FPM_SOCK` | `/run/php/php8.2-fpm.sock` | сокет php-fpm |

`spot/config.yml` дополнительно задаёт `DEPLOY_TO`, `VERSION_DIR`, `CURRENT_DIR`,
`SHARED_DIR`, `SHARED_PATHS`, `PHP_BIN` и `RELOAD_NGINX`
(`systemctl reload nginx`; на хостах без systemd переопределяется через
`-e RELOAD_NGINX:"service nginx reload"`).

```bash
export VERSION="$(git rev-parse --short HEAD)"
export SERVER_NAME=hello.example.com HTTP_PORT=80 PHP_FPM_SOCK=/run/php/php8.2-fpm.sock
export DEPLOY_HOST=203.0.113.10 DEPLOY_PORT=22 DEPLOY_USER=deploy

examples/hello/scripts/render.sh
export SOURCE="$(examples/hello/scripts/build-release.sh "$VERSION")"

cd examples/hello/spot
spot --no-color \
  --playbook spot.yml \
  --task=deploy \
  --target=hello \
  --inventory=inventory.yml \
  --env-file config.yml \
  --key ~/.ssh/deploy_key
```

Проверить playbook без изменений: `spot --local --dry ...` (как в job `validate`).

## Деплой из GitHub Actions

Workflow `.github/workflows/hello.yml`:

- `validate` — рендерит шаблоны, собирает архив и прогоняет `spot --local --dry`;
- `sandbox` — запускает `test/sandbox.sh` на одноразовом Docker-хосте;
- `deploy` — только при `workflow_dispatch` с `deploy: true`, использует настоящий сервер.

Repository variables:

| Переменная | Обязательна | Пример |
| --- | --- | --- |
| `HELLO_DEPLOY_HOST` | да | `203.0.113.10` |
| `HELLO_DEPLOY_PORT` | нет (22) | `2222` |
| `HELLO_DEPLOY_USER` | нет (`deploy`) | `deploy` |
| `HELLO_SERVER_NAME` | нет (`hello.test`) | `hello.example.com` |
| `HELLO_HTTP_PORT` | нет (`80`) | `80` |
| `HELLO_PHP_FPM_SOCK` | нет (`/run/php/php8.2-fpm.sock`) | `/run/php/php8.3-fpm.sock` |

Secret: `HELLO_DEPLOY_KEY` — приватный SSH-ключ деплоя.

Запуск: **Actions → Hello example (spot + gomplate) → Run workflow → deploy: true**.

## Ограничения примера

- Рассчитан на Debian/Ubuntu с systemd и пакетным nginx/php-fpm.
- Один сервер; для нескольких хостов достаточно добавить их в inventory.
- `current` и `releases` живут в `/var/www/hello`; путь меняется в `config.yml`.
- Миграций/очистки кеша приложения нет — в отличие от боевого проекта, здесь нечего мигрировать.
- Демо использует `NOPASSWD:ALL` для `deploy`; для продакшена ограничьте sudo.
