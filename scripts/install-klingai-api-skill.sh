#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-openclaw}"
REPO_URL="${REPO_URL:-https://github.com/puboc/klingai_api_skill.git}"
REPO_REF="${REPO_REF:-main}"
SKILL_GITHUB_TOKEN="${SKILL_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"
USER_OPENCLAW_HOME="${OPENCLAW_HOME-}"
USER_WORKSPACE_DIR="${WORKSPACE_DIR-}"
USER_SKILLS_DIR="${SKILLS_DIR-}"
USER_WORKSPACE_SKILLS_DIR="${WORKSPACE_SKILLS_DIR-}"
DEFAULT_OPENCLAW_HOME="${HOME:-/root}/.openclaw"
if [[ -z "${OPENCLAW_HOME:-}" && -d /data ]]; then
  DEFAULT_OPENCLAW_HOME="/data/.openclaw"
fi
OPENCLAW_HOME="${OPENCLAW_HOME:-${DEFAULT_OPENCLAW_HOME}}"
WORKSPACE_DIR="${WORKSPACE_DIR:-${OPENCLAW_HOME}/workspace}"
SKILLS_DIR="${SKILLS_DIR:-${OPENCLAW_HOME}/skills}"
SKILL_NAME="${SKILL_NAME:-klingai_api_skill}"
SKILL_ALIAS="${SKILL_ALIAS:-klingai}"
SKILL_DIR="${SKILLS_DIR}/${SKILL_NAME}"
REPO_DIR="${WORKSPACE_DIR}/${SKILL_NAME}-source"
WORKSPACE_SKILLS_DIR="${WORKSPACE_SKILLS_DIR:-${WORKSPACE_DIR}/skills}"
WORKSPACE_SKILL_LINK="${WORKSPACE_SKILLS_DIR}/${SKILL_NAME}"
WORKSPACE_SKILL_ALIAS_LINK="${WORKSPACE_SKILLS_DIR}/${SKILL_ALIAS}"
STATUS_LOG_FILE="${STATUS_LOG_FILE:-/tmp/klingai-api-skill-install.log}"

log_status() {
  local message="$1"
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${message}" >> "${STATUS_LOG_FILE}"
}

is_inside_container() {
  if [[ -f "/.dockerenv" ]]; then
    return 0
  fi
  grep -qaE '(docker|containerd|kubepods)' /proc/1/cgroup 2>/dev/null
}

is_placeholder_value() {
  case "${1:-}" in
    ""|"null"|"undefined"|"klingApiKey"|"klingAccessKeyId"|"klingSecretKey"|"klingApiSecret"|"klingSecretAccessKey"|"klingApiBase")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_kling_credentials() {
  local access_key api_key secret_key secret_alias api_secret

  access_key="${KLING_ACCESS_KEY_ID:-}"
  api_key="${KLING_API_KEY:-}"
  secret_key="${KLING_SECRET_ACCESS_KEY:-}"
  secret_alias="${KLING_SECRET_KEY:-}"
  api_secret="${KLING_API_SECRET:-}"

  if is_placeholder_value "${access_key}"; then access_key=""; fi
  if is_placeholder_value "${api_key}"; then api_key=""; fi
  if is_placeholder_value "${secret_key}"; then secret_key=""; fi
  if is_placeholder_value "${secret_alias}"; then secret_alias=""; fi
  if is_placeholder_value "${api_secret}"; then api_secret=""; fi

  KLING_ACCESS_KEY_ID="${access_key:-${api_key}}"
  KLING_SECRET_ACCESS_KEY="${secret_key:-${secret_alias:-${api_secret}}}"

  if is_placeholder_value "${KLING_API_BASE:-}"; then
    KLING_API_BASE=""
  fi

  if [[ -z "${KLING_SECRET_ACCESS_KEY}" && "${KLING_ACCESS_KEY_ID}" == *:* ]]; then
    KLING_SECRET_ACCESS_KEY="${KLING_ACCESS_KEY_ID#*:}"
    KLING_ACCESS_KEY_ID="${KLING_ACCESS_KEY_ID%%:*}"
  fi
}

normalize_kling_credentials

if [[ -z "${KLING_ACCESS_KEY_ID}" || -z "${KLING_SECRET_ACCESS_KEY}" ]]; then
  echo "Missing Kling API credentials. Export KLING_ACCESS_KEY_ID and KLING_SECRET_ACCESS_KEY before installing." >&2
  echo "KLING_API_KEY is accepted as an alias for KLING_ACCESS_KEY_ID; use KLING_SECRET_KEY or KLING_API_SECRET for the secret." >&2
  exit 1
fi

build_clone_url() {
  local url="$1"
  local token="${2:-${SKILL_GITHUB_TOKEN:-}}"
  case "${url}" in
    https://github.com/*)
      if [[ -n "${token}" ]]; then
        printf 'https://x-access-token:%s@github.com/%s' "${token}" "${url#https://github.com/}"
      else
        printf '%s' "${url}"
      fi
      ;;
    *)
      printf '%s' "${url}"
      ;;
  esac
}

if ! is_inside_container; then
  if command -v docker >/dev/null 2>&1 && docker inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    log_status "Installing Kling AI API skill inside container ${CONTAINER_NAME}"
    docker_env=(
      -e REPO_URL="${REPO_URL}" \
      -e REPO_REF="${REPO_REF}" \
      -e SKILL_GITHUB_TOKEN="${SKILL_GITHUB_TOKEN}" \
      -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
      -e SKILL_NAME="${SKILL_NAME}" \
      -e SKILL_ALIAS="${SKILL_ALIAS}" \
      -e KLING_ACCESS_KEY_ID="${KLING_ACCESS_KEY_ID}" \
      -e KLING_SECRET_ACCESS_KEY="${KLING_SECRET_ACCESS_KEY}" \
      -e KLING_API_BASE="${KLING_API_BASE:-}"
    )
    if [[ -n "${KLING_STORAGE_ROOT:-}" ]]; then docker_env+=(-e KLING_STORAGE_ROOT="${KLING_STORAGE_ROOT}"); fi
    if [[ -n "${USER_OPENCLAW_HOME}" ]]; then docker_env+=(-e OPENCLAW_HOME="${USER_OPENCLAW_HOME}"); fi
    if [[ -n "${USER_WORKSPACE_DIR}" ]]; then docker_env+=(-e WORKSPACE_DIR="${USER_WORKSPACE_DIR}"); fi
    if [[ -n "${USER_SKILLS_DIR}" ]]; then docker_env+=(-e SKILLS_DIR="${USER_SKILLS_DIR}"); fi
    if [[ -n "${USER_WORKSPACE_SKILLS_DIR}" ]]; then docker_env+=(-e WORKSPACE_SKILLS_DIR="${USER_WORKSPACE_SKILLS_DIR}"); fi
    exec docker exec \
      "${docker_env[@]}" \
      "${CONTAINER_NAME}" \
      bash -s < "${BASH_SOURCE[0]}"
  fi
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd node
need_cmd tar

mkdir -p "${WORKSPACE_DIR}" "${SKILLS_DIR}" "${WORKSPACE_SKILLS_DIR}"
clone_url="$(build_clone_url "${REPO_URL}")"

if [[ -d "${REPO_DIR}/.git" ]]; then
  git -C "${REPO_DIR}" remote set-url origin "${clone_url}"
  git -C "${REPO_DIR}" fetch --prune origin
  if git -C "${REPO_DIR}" rev-parse --verify --quiet "origin/${REPO_REF}" >/dev/null; then
    git -C "${REPO_DIR}" checkout -B "${REPO_REF}" "origin/${REPO_REF}"
  else
    git -C "${REPO_DIR}" checkout "${REPO_REF}"
  fi
else
  rm -rf "${REPO_DIR}"
  git clone "${clone_url}" "${REPO_DIR}"
  if git -C "${REPO_DIR}" rev-parse --verify --quiet "origin/${REPO_REF}" >/dev/null; then
    git -C "${REPO_DIR}" checkout -B "${REPO_REF}" "origin/${REPO_REF}"
  else
    git -C "${REPO_DIR}" checkout "${REPO_REF}"
  fi
fi

if [[ ! -f "${REPO_DIR}/SKILL.md" ]]; then
  echo "Kling AI API skill source missing SKILL.md: ${REPO_DIR}" >&2
  exit 1
fi

rm -rf "${SKILL_DIR}"
mkdir -p "${SKILL_DIR}"
tar --exclude='.git' --exclude='node_modules' --exclude='.cache' --exclude='.env' -C "${REPO_DIR}" -cf - . | tar -C "${SKILL_DIR}" -xf -

export KLING_ACCESS_KEY_ID
export KLING_SECRET_ACCESS_KEY
if [[ -n "${KLING_STORAGE_ROOT:-}" ]]; then
  export KLING_STORAGE_ROOT
fi
node "${SKILL_DIR}/scripts/kling.mjs" account --import-env >/dev/null

if [[ -n "${KLING_API_BASE:-}" ]]; then
  kling_config_dir="${KLING_STORAGE_ROOT:-${HOME:-/root}/.config/kling}"
  mkdir -p "${kling_config_dir}"
  printf 'KLING_API_BASE=%s\n' "${KLING_API_BASE}" > "${kling_config_dir}/kling.env"
  chmod 0600 "${kling_config_dir}/kling.env"
fi

node "${SKILL_DIR}/scripts/kling.mjs" --help >/dev/null

rm -rf "${WORKSPACE_SKILL_LINK}"
ln -s "${SKILL_DIR}" "${WORKSPACE_SKILL_LINK}"
if [[ -n "${SKILL_ALIAS}" && "${SKILL_ALIAS}" != "${SKILL_NAME}" ]]; then
  if [[ -e "${WORKSPACE_SKILL_ALIAS_LINK}" && ! -L "${WORKSPACE_SKILL_ALIAS_LINK}" ]]; then
    log_status "Skipped alias link because a non-symlink path already exists: ${WORKSPACE_SKILL_ALIAS_LINK}"
  else
    rm -f "${WORKSPACE_SKILL_ALIAS_LINK}"
    ln -s "${SKILL_DIR}" "${WORKSPACE_SKILL_ALIAS_LINK}"
  fi
fi

log_status "Installed Kling AI API skill at ${SKILL_DIR} with credentials imported"
echo "Installed ${SKILL_NAME} at ${SKILL_DIR}"
echo "Workspace link: ${WORKSPACE_SKILL_LINK} -> ${SKILL_DIR}"
if [[ -n "${SKILL_ALIAS}" && "${SKILL_ALIAS}" != "${SKILL_NAME}" && -L "${WORKSPACE_SKILL_ALIAS_LINK}" ]]; then
  echo "Workspace alias: ${WORKSPACE_SKILL_ALIAS_LINK} -> ${SKILL_DIR}"
fi
