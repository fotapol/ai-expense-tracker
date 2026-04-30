#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/expense_tracker_app"
ANDROID_DIR="$APP_DIR/android"
ANDROID_APP_DIR="$ANDROID_DIR/app"
KEY_PROPERTIES_FILE="$ANDROID_DIR/key.properties"
AAB_PATH="$APP_DIR/build/app/outputs/bundle/release/app-release.aab"

EXPECTED_API_BASE_URL="https://api.nexavend.store:8443"
EXPECTED_PRIVACY_URL="https://nexavend.store/privacy"
EXPECTED_TERMS_URL="https://nexavend.store/terms"
EXPECTED_DELETE_ACCOUNT_URL="https://nexavend.store/delete-account"
EXPECTED_SUPPORT_EMAIL="support@nexavend.store"

fail() {
  echo "error: $*" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

reject_local_url() {
  local name="$1"
  local value="$2"
  if [[ "$value" =~ (10\.0\.2\.2|localhost|127\.0\.0\.1) ]]; then
    fail "$name must not use emulator or local URLs in production builds"
  fi
}

require_nonempty() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$(trim "$value")" ]]; then
    fail "$name is required"
  fi
}

require_exact() {
  local name="$1"
  local expected="$2"
  local value="${!name:-}"
  if [[ -z "$(trim "$value")" ]]; then
    fail "$name is required"
  fi
  reject_local_url "$name" "$value"
  if [[ "$value" != "$expected" ]]; then
    fail "$name must be $expected"
  fi
}

declare -A KEY_PROPERTIES=()
if [[ -f "$KEY_PROPERTIES_FILE" ]]; then
  while IFS='=' read -r raw_key raw_value || [[ -n "${raw_key:-}" ]]; do
    key="$(trim "${raw_key:-}")"
    value="$(trim "${raw_value:-}")"
    if [[ -z "$key" || "$key" == \#* ]]; then
      continue
    fi
    KEY_PROPERTIES["$key"]="$value"
  done < "$KEY_PROPERTIES_FILE"
fi

property_or_env() {
  local property_name="$1"
  local env_name="$2"
  local value="${KEY_PROPERTIES[$property_name]:-}"
  if [[ -z "$(trim "$value")" ]]; then
    value="${!env_name:-}"
  fi
  trim "$value"
}

resolve_store_file() {
  local raw_store_file="$1"
  if [[ "$raw_store_file" =~ ^/ || "$raw_store_file" =~ ^[A-Za-z]:[\\/] ]]; then
    printf '%s' "$raw_store_file"
  else
    printf '%s/%s' "$ANDROID_APP_DIR" "$raw_store_file"
  fi
}

require_exact API_BASE_URL "$EXPECTED_API_BASE_URL"
require_nonempty REVENUECAT_ANDROID_API_KEY
require_exact APP_PRIVACY_URL "$EXPECTED_PRIVACY_URL"
require_exact APP_TERMS_URL "$EXPECTED_TERMS_URL"
require_exact APP_DELETE_ACCOUNT_URL "$EXPECTED_DELETE_ACCOUNT_URL"
require_exact APP_SUPPORT_EMAIL "$EXPECTED_SUPPORT_EMAIL"

STORE_FILE="$(property_or_env storeFile ANDROID_KEYSTORE_FILE)"
STORE_PASSWORD="$(property_or_env storePassword ANDROID_KEYSTORE_PASSWORD)"
KEY_ALIAS="$(property_or_env keyAlias ANDROID_KEY_ALIAS)"
KEY_PASSWORD="$(property_or_env keyPassword ANDROID_KEY_PASSWORD)"

[[ -n "$STORE_FILE" ]] || fail "release signing storeFile or ANDROID_KEYSTORE_FILE is required"
[[ -n "$STORE_PASSWORD" ]] || fail "release signing storePassword or ANDROID_KEYSTORE_PASSWORD is required"
[[ -n "$KEY_ALIAS" ]] || fail "release signing keyAlias or ANDROID_KEY_ALIAS is required"
[[ -n "$KEY_PASSWORD" ]] || fail "release signing keyPassword or ANDROID_KEY_PASSWORD is required"
[[ "${KEY_ALIAS,,}" != "androiddebugkey" ]] || fail "release builds must not use androiddebugkey"

RESOLVED_STORE_FILE="$(resolve_store_file "$STORE_FILE")"
[[ -f "$RESOLVED_STORE_FILE" ]] || fail "release keystore file not found: $RESOLVED_STORE_FILE"

reject_local_url APP_PLAY_SUBSCRIPTIONS_URL "${APP_PLAY_SUBSCRIPTIONS_URL:-}"

DART_DEFINES=(
  "--dart-define=API_BASE_URL=$API_BASE_URL"
  "--dart-define=REVENUECAT_ANDROID_API_KEY=$REVENUECAT_ANDROID_API_KEY"
  "--dart-define=APP_PRIVACY_URL=$APP_PRIVACY_URL"
  "--dart-define=APP_TERMS_URL=$APP_TERMS_URL"
  "--dart-define=APP_DELETE_ACCOUNT_URL=$APP_DELETE_ACCOUNT_URL"
  "--dart-define=APP_SUPPORT_EMAIL=$APP_SUPPORT_EMAIL"
)

if [[ -n "${APP_PLAY_SUBSCRIPTIONS_URL:-}" ]]; then
  DART_DEFINES+=("--dart-define=APP_PLAY_SUBSCRIPTIONS_URL=$APP_PLAY_SUBSCRIPTIONS_URL")
fi

pushd "$APP_DIR" >/dev/null
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release "${DART_DEFINES[@]}"
popd >/dev/null

[[ -f "$AAB_PATH" ]] || fail "expected Android App Bundle was not produced: $AAB_PATH"
echo "Built production Android App Bundle: $AAB_PATH"
