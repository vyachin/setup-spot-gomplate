# setup-spot-gomplate

Composite GitHub Action, которая ставит закреплённые версии [spot](https://github.com/umputun/spot)
и [gomplate](https://github.com/hairyhenderson/gomplate) для использования в CI/CD.

Установка вынесена из workflow в отдельный action: версии задаются параметрами, бинарники
проверяются по SHA-256 из релиза, кэшируются между запусками и попадают в `PATH`.

## Использование

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install spot and gomplate
        uses: vyachin/setup-spot-gomplate@v0.0.1
        with:
          spot-version: v1.20.1
          gomplate-version: v5.3.1

      - run: spot --version && gomplate --version
```

В workflow этого же репозитория — `uses: ./`.

Версии удобно держать в `env`, чтобы не дублировать их по job-ам:

```yaml
env:
  SPOT_VERSION: v1.20.1
  GOMPLATE_VERSION: v5.3.1

steps:
  - uses: vyachin/setup-spot-gomplate@v0.0.1
    with:
      spot-version: ${{ env.SPOT_VERSION }}
      gomplate-version: ${{ env.GOMPLATE_VERSION }}
```

## Входы и выходы

| Вход | По умолчанию | Назначение |
| --- | --- | --- |
| `spot-version` | `v1.20.1` | Тег релиза spot. |
| `gomplate-version` | `v5.3.1` | Тег релиза gomplate. |
| `cache` | `true` | Кэшировать бинарники между запусками (`false`, если кэш не нужен). |

| Выход | Назначение |
| --- | --- |
| `spot-path` | Абсолютный путь к `spot`. |
| `gomplate-path` | Абсолютный путь к `gomplate`. |

Оба бинарника также добавляются в `PATH`.

## Что делает action

- Определяет платформу по `uname -s`/`uname -m`: Linux и macOS, x86_64 и arm64.
- Скачивает файлы выбранного релиза с GitHub.
- Сверяет SHA-256 с checksums из этого же релиза.
- Кладёт бинарники в `$RUNNER_TEMP/spot-gomplate` и пишет каталог в `$GITHUB_PATH`.
- Идемпотентен: если нужные версии уже установлены (например, после restore кэша),
  повторно ничего не скачивает.
- Кэш (`actions/cache`) имеет ключ из ОС, архитектуры и обеих версий, поэтому смена версии
  автоматически инвалидирует его.

Windows не поддерживается.

## Локальный запуск

`install.sh` не зависит от GitHub Actions и работает на Linux/macOS:

```bash
SPOT_VERSION=v1.20.1 \
GOMPLATE_VERSION=v5.3.1 \
INSTALL_DIR="$HOME/.local/bin" \
  bash ./install.sh
```

## Обновление версий

1. Поменяйте `spot-version` / `gomplate-version` в workflow.
2. Убедитесь, что в релизе есть ожидаемые имена файлов:
   - spot: `spot_<версия>_<платформа>.tar.gz` и `spot_<версия без v>_checksums.txt`;
   - gomplate: `gomplate_<платформа>` и `checksums-<версия>_sha256.txt`.
3. Прогоните [test-action.yml](.github/workflows/test-action.yml): action упадёт, если
   контрольная сумма не совпадёт или файла нет.

## Состав репозитория

| Путь | Назначение |
| --- | --- |
| [action.yml](action.yml) | Метаданные action: входы, выходы, кэш, запуск установки. |
| [install.sh](install.sh) | Определение платформы, скачивание, проверка checksums, установка. |
| [.github/workflows/test-action.yml](.github/workflows/test-action.yml) | Тесты action на Linux/macOS, с кэшем и без. |
| [.github/workflows/hello.yml](.github/workflows/hello.yml) | Пример CI/CD: деплой hello-приложения. |
| [examples/hello](examples/hello/README.md) | PHP-приложение, zero-downtime деплой, nginx, cron. |

## Тесты

`test-action.yml` проверяет:

- установку на `ubuntu-latest` (с кэшем) и `macos-latest` (без кэша);
- outputs `spot-path` / `gomplate-path` и наличие команд в `PATH`;
- точные версии spot и gomplate;
- повторный запуск (идемпотентность);
- реальный вызов `gomplate` на шаблонах из `examples/hello/spot`.

`hello.yml` дополнительно поднимает одноразовый Docker-хост и проверяет сам деплой:
zero downtime, nginx-конфиг и cron.

## Релизы

Для использования из другого репозитория поставьте тег:

```bash
git tag -a v0.0.1 -m "setup-spot-gomplate v0.0.1"
git push origin v0.0.1
```

Для максимальной безопасности в чужом CI можно пинить не тег, а commit SHA:
`vyachin/setup-spot-gomplate@<sha>`.
