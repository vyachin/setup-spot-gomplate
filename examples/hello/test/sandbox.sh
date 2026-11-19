#!/usr/bin/env bash
#
# End-to-end check for examples/hello. It starts a disposable Debian container
# with sshd, nginx, php-fpm and cron, then deploys the example to it with spot.
#
# Requires: docker, spot, gomplate, ssh, ssh-keygen, curl.
# The tools can be installed with ./.github/actions/setup-spot-gomplate/action.yml,
# or locally by running its install.sh.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
example_dir="$(cd "$script_dir/.." && pwd)"

container="hello-spot-sandbox-$$"
image="hello-spot-sandbox:$$"
work="$(mktemp -d "${TMPDIR:-/tmp}/hello-sandbox.XXXXXX")"
container_started=""

cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ -n "$container_started" ]; then
    echo "--- container logs (tail) ---" >&2
    docker logs "$container" 2>&1 | tail -n 80 >&2 || true
  fi
  if [ -n "$container_started" ]; then
    docker rm -f "$container" >/dev/null 2>&1 || true
  fi
  docker rmi -f "$image" >/dev/null 2>&1 || true
  rm -rf "$work"
  exit "$status"
}
trap cleanup EXIT

pass() { printf 'ok - %s\n' "$*"; }
fail() { printf 'FAIL - %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || fail "required command '$1' is not installed"
}

need docker
need spot
need gomplate
need ssh
need ssh-keygen
need curl

echo "==> building sandbox image"
docker build -q -t "$image" "$script_dir" >/dev/null

ssh-keygen -q -t ed25519 -N '' -f "$work/id_ed25519"

echo "==> starting sandbox"
docker run -d --name "$container" \
  -p 127.0.0.1::2222 -p 127.0.0.1::80 \
  -v "$work:/keys:ro" \
  "$image" >/dev/null
container_started=1

ssh_port="$(docker port "$container" 2222/tcp | head -n 1 | awk -F: '{print $NF}')"
public_port="$(docker port "$container" 80/tcp | head -n 1 | awk -F: '{print $NF}')"
[ -n "$ssh_port" ] || fail "could not determine the sandbox SSH port"
[ -n "$public_port" ] || fail "could not determine the sandbox HTTP port"

for _ in $(seq 1 60); do
  if ssh -i "$work/id_ed25519" -p "$ssh_port" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=2 -o LogLevel=ERROR \
      deploy@127.0.0.1 true 2>/dev/null; then
    break
  fi
  sleep 1
done
ssh -i "$work/id_ed25519" -p "$ssh_port" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=2 -o LogLevel=ERROR \
  deploy@127.0.0.1 true 2>/dev/null || fail "sandbox SSH did not start"

# A crontab entry that does not belong to the example must survive deployments.
docker exec "$container" sh -c 'printf "5 4 * * * echo keep-me\n" | crontab -u deploy -'

export SERVER_NAME="hello.test"
export HTTP_PORT="80"
export PHP_FPM_SOCK="/run/php/php8.2-fpm.sock"
export DEPLOY_HOST="127.0.0.1"
export DEPLOY_PORT="$ssh_port"
export DEPLOY_USER="deploy"

render() {
  VERSION="$1" bash "$example_dir/scripts/render.sh" >/dev/null
}

make_release() {
  local version="$1"
  bash "$example_dir/scripts/build-release.sh" "$version" "$work/build/hello-$version.tar.gz" >/dev/null
  printf '%s\n' "$work/build/hello-$version.tar.gz"
}

deploy() {
  local version="$1" source="$2"
  local spot_args=(
    --playbook spot.yml
    --task=deploy
    --target=hello
    --inventory=inventory.yml
    --env-file config.yml
    --key "$work/id_ed25519"
    -e RELOAD_NGINX:"service nginx reload"
  )
  if [ -n "${SPOT_VERBOSE:-}" ]; then
    spot_args+=(--verbose)
  fi
  (
    cd "$example_dir/spot"
    SOURCE="$source" \
    VERSION="$version" \
    SERVER_NAME="$SERVER_NAME" \
    HTTP_PORT="$HTTP_PORT" \
    PHP_FPM_SOCK="$PHP_FPM_SOCK" \
    spot --no-color "${spot_args[@]}"
  )
}

fetch_body() {
  curl -fsS --max-time 5 -H "Host: $SERVER_NAME" "http://127.0.0.1:$public_port/"
}

release_header() {
  curl -fsS --max-time 5 -D - -o /dev/null -H "Host: $SERVER_NAME" "http://127.0.0.1:$public_port/" \
    | tr -d '\r' \
    | awk -F': ' 'tolower($1) == "x-hello-release" { print $2; exit }'
}

assert_body_contains() {
  local expected="$1" body
  body="$(fetch_body)" || fail "GET / failed"
  case "$body" in
    *"$expected"*) pass "GET / serves release $expected" ;;
    *) fail "GET / does not mention release $expected" ;;
  esac
}

version_a="a-$(date +%s)"
version_b="b-$(date +%s)"
version_c="c-$(date +%s)"

render "$version_a"

echo "==> first deploy: $version_a"
deploy "$version_a" "$(make_release "$version_a")"
assert_body_contains "$version_a"
[ "$(release_header)" = "$version_a" ] || fail "X-Hello-Release is '$(release_header)', expected '$version_a'"
pass "nginx config was rendered and reloaded for $version_a"

echo "==> second deploy under continuous load: $version_b"
sleep 1
: > "$work/load.log"
(
  while [ ! -f "$work/stop-load" ]; do
    if curl -fsS --max-time 2 -H "Host: $SERVER_NAME" "http://127.0.0.1:$public_port/" >/dev/null 2>&1; then
      echo ok >> "$work/load.log"
    else
      echo fail >> "$work/load.log"
    fi
  done
) &
loader=$!

sleep 1
deploy "$version_b" "$(make_release "$version_b")"
touch "$work/stop-load"
wait "$loader" 2>/dev/null || true

load_total="$(wc -l < "$work/load.log" | tr -d ' ')"
load_failures="$(grep -c '^fail$' "$work/load.log" 2>/dev/null || true)"
[ "$load_total" -gt 0 ] || fail "the load generator sent no requests"
[ "$load_failures" -eq 0 ] || fail "$load_failures of $load_total requests failed during deploy"
pass "zero downtime: $load_total requests, 0 failures"
assert_body_contains "$version_b"
[ "$(release_header)" = "$version_b" ] || fail "X-Hello-Release is '$(release_header)', expected '$version_b'"

echo "==> third deploy: $version_c"
sleep 1
deploy "$version_c" "$(make_release "$version_c")"
assert_body_contains "$version_c"

current_path="$(docker exec "$container" readlink -f /var/www/hello/current)"
[ -n "$current_path" ] || fail "the current symlink is missing"

release_count="$(docker exec "$container" sh -c 'find /var/www/hello/releases -mindepth 1 -maxdepth 1 -type d | wc -l' | tr -d ' ')"
[ "$release_count" -eq 3 ] || fail "expected 3 releases after three deploys, found $release_count"
pass "old releases are pruned (3 kept)"

crontab="$(docker exec "$container" crontab -l -u deploy)"
case "$crontab" in
  *"$current_path/bin/cron.php"*) pass "cron points to the active release" ;;
  *) fail "cron does not point to $current_path/bin/cron.php" ;;
esac
[ "$(printf '%s\n' "$crontab" | grep -c '^# BEGIN hello-example (managed by spot)$' || true)" -eq 1 ] \
  || fail "the managed cron block is not unique"
[ "$(printf '%s\n' "$crontab" | grep -c '^# END hello-example (managed by spot)$' || true)" -eq 1 ] \
  || fail "the managed cron block has no matching END marker"
case "$crontab" in
  *"echo keep-me"*) pass "unrelated crontab entries are preserved" ;;
  *) fail "the pre-existing crontab entry was removed" ;;
esac

docker exec "$container" sh -c "test -L '$current_path/log'" || fail "the shared log directory is not linked into the release"
docker exec "$container" service cron status >/dev/null 2>&1 || fail "the cron daemon is not running"
pass "shared directories and cron daemon look healthy"

echo "all hello example checks passed"
