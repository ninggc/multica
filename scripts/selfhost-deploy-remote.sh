#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-}"
DEPLOY_APP_USER="${DEPLOY_APP_USER:-}"
DEPLOY_RUN_ID="${DEPLOY_RUN_ID:-}"
DEPLOY_SHA="${DEPLOY_SHA:-}"
DEPLOY_REPO="${DEPLOY_REPO:-}"

if [[ -z "${DEPLOY_DIR}" ]]; then
  echo "DEPLOY_DIR is required" >&2
  exit 1
fi

if [[ -z "${DEPLOY_APP_USER}" ]]; then
  echo "DEPLOY_APP_USER is required" >&2
  exit 1
fi

if [[ -z "${DEPLOY_RUN_ID}" ]]; then
  echo "DEPLOY_RUN_ID is required" >&2
  exit 1
fi

if [[ -z "${DEPLOY_SHA}" ]]; then
  echo "DEPLOY_SHA is required" >&2
  exit 1
fi

if [[ -z "${DEPLOY_REPO}" ]]; then
  echo "DEPLOY_REPO is required" >&2
  exit 1
fi

deploy_tmp="/tmp/multica-deploy-${DEPLOY_RUN_ID}"
archive_path="${deploy_tmp}/multica-deploy-assets.tgz"
bundle_path="${deploy_tmp}/multica-deploy.bundle"
backup_script="${deploy_tmp}/scripts/selfhost-backup.sh"
had_git_worktree=false

if [[ ! -f "${archive_path}" ]]; then
  echo "deploy archive not found: ${archive_path}" >&2
  exit 1
fi

mkdir -p "${deploy_tmp}/scripts"
tar -xzf "${archive_path}" -C "${deploy_tmp}"
chmod +x "${backup_script}"

if sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  had_git_worktree=true
  "${backup_script}" "${DEPLOY_DIR}" "${DEPLOY_APP_USER}" "${DEPLOY_SHA}"
else
  sudo mkdir -p "$(dirname "${DEPLOY_DIR}")"
  sudo -u "${DEPLOY_APP_USER}" mkdir -p "${DEPLOY_DIR}"
  sudo -u "${DEPLOY_APP_USER}" git init "${DEPLOY_DIR}"
fi

sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" fetch "${bundle_path}" HEAD
if [[ "${had_git_worktree}" == "true" ]]; then
  sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" reset --hard FETCH_HEAD
else
  sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" checkout --force -B main FETCH_HEAD
fi
sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" clean -fd -e .env
if sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" remote get-url origin >/dev/null 2>&1; then
  sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" remote set-url origin "git@github.com:${DEPLOY_REPO}.git"
else
  sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" remote add origin "git@github.com:${DEPLOY_REPO}.git"
fi

sudo docker compose -f "${DEPLOY_DIR}/docker-compose.selfhost.yml" up -d --build

curl -fsS http://127.0.0.1:8080/health
curl -fsSI http://127.0.0.1:3000 >/dev/null

sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" rev-parse --short HEAD
sudo -u "${DEPLOY_APP_USER}" git -C "${DEPLOY_DIR}" status --short
sudo docker compose -f "${DEPLOY_DIR}/docker-compose.selfhost.yml" ps

sudo rm -rf "${deploy_tmp}"
