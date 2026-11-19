# setup-spot-gomplate

Composite GitHub Action, которая ставит закреплённые версии
[spot](https://github.com/umputun/spot) и [gomplate](https://github.com/hairyhenderson/gomplate)
для использования в CI/CD.

Версии задаются параметрами, бинарники проверяются по SHA-256 из релиза, кэшируются между
запусками и добавляются в `PATH`.

## Подключение

### Из другого репозитория

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install spot and gomplate
        uses: vyachin/setup-spot-gomplate@main
        with:
          spot-version: v1.20.1
          gomplate-version: v5.3.1

      - name: Check tools
        run: |
          spot --version
          gomplate --version
```

Сейчас тег не создан, поэтому в примере указан `@main`. Для стабильного использования
поставьте тег и замените ссылку на `@v0.0.1` или на commit SHA:

```yaml
- uses: vyachin/setup-spot-gomplate@v0.0.1
```

### В этом же репозитории

```yaml
steps:
  - uses: actions/checkout@v7
  - uses: ./
    with:
      spot-version: v1.20.1
      gomplate-version: v5.3.1
```

### Пример использования в деплое

```yaml
- name: Install spot and gomplate
  uses: vyachin/setup-spot-gomplate@main
  with:
    spot-version: v1.20.1
    gomplate-version: v5.3.1

- name: Render deploy templates
  run: |
    gomplate \
      --input-dir deploy \
      --include '*.tmpl' \
      --output-map '{{ .in | strings.TrimSuffix ".tmpl" }}'

- name: Deploy with spot
  working-directory: deploy
  env:
    SOURCE: ${{ runner.temp }}/release.tar.gz
    VERSION: ${{ github.sha }}
  run: |
    spot --no-color \
      --playbook spot.yml \
      --task=deploy \
      --target=web \
      --env-file config.yml \
      --key "$RUNNER_TEMP/deploy_key"
```

Версии удобно держать в `env`, чтобы не дублировать их по job-ам:

```yaml
env:
  SPOT_VERSION: v1.20.1
  GOMPLATE_VERSION: v5.3.1

steps:
  - uses: vyachin/setup-spot-gomplate@main
    with:
      spot-version: ${{ env.SPOT_VERSION }}
      gomplate-version: ${{ env.GOMPLATE_VERSION }}
```

## Входы

| Вход | По умолчанию | Назначение |
| --- | --- | --- |
| `spot-version` | `v1.20.1` | Тег релиза spot. |
| `gomplate-version` | `v5.3.1` | Тег релиза gomplate. |
| `cache` | `true` | Кэшировать бинарники между запусками (`false`, если кэш не нужен). |

## Выходы

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
3. Action упадёт, если контрольная сумма не совпадёт или файла нет.
