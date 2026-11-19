# setup-spot-gomplate

Composite GitHub Action that installs pinned versions of
[spot](https://github.com/umputun/spot) and [gomplate](https://github.com/hairyhenderson/gomplate)
for use in CI/CD.

Versions are selected through inputs. The binaries are verified against the SHA-256 checksums
published with the release, cached between workflow runs and added to `PATH`.

## Usage

### From another repository

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

The tag has not been created yet, so the example uses `@main`. For stable usage, create a tag
and pin `@v0.0.1` or a commit SHA:

```yaml
- uses: vyachin/setup-spot-gomplate@v0.0.1
```

### In the same repository

```yaml
steps:
  - uses: actions/checkout@v7
  - uses: ./
    with:
      spot-version: v1.20.1
      gomplate-version: v5.3.1
```

### Deploy example

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

Keeping the versions in `env` avoids repeating them in every job:

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

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `spot-version` | `v1.20.1` | spot release tag. |
| `gomplate-version` | `v5.3.1` | gomplate release tag. |
| `cache` | `true` | Cache the binaries between runs (`false` to disable). |

## Outputs

| Output | Description |
| --- | --- |
| `spot-path` | Absolute path to the `spot` binary. |
| `gomplate-path` | Absolute path to the `gomplate` binary. |

Both binaries are also added to `PATH`.

## What the action does

- Detects the platform with `uname -s`/`uname -m`: Linux and macOS, x86_64 and arm64.
- Downloads the selected release assets from GitHub.
- Verifies SHA-256 against the checksums published with that release.
- Installs the binaries into `$RUNNER_TEMP/spot-gomplate` and adds the directory to `$GITHUB_PATH`.
- Is idempotent: if the requested versions are already installed (for example, after a cache
  restore), it does not download them again.
- The `actions/cache` key includes the OS, architecture and both versions, so changing a version
  invalidates the cache automatically.

Windows is not supported.

## Local usage

`install.sh` does not depend on GitHub Actions and works on Linux/macOS:

```bash
SPOT_VERSION=v1.20.1 \
GOMPLATE_VERSION=v5.3.1 \
INSTALL_DIR="$HOME/.local/bin" \
  bash ./install.sh
```

## Updating versions

1. Change `spot-version` / `gomplate-version` in the workflow.
2. Make sure the release contains the expected asset names:
   - spot: `spot_<version>_<platform>.tar.gz` and `spot_<version without v>_checksums.txt`;
   - gomplate: `gomplate_<platform>` and `checksums-<version>_sha256.txt`.
3. The action fails if a checksum does not match or an asset is missing.
