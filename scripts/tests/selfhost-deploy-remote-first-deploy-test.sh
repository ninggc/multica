#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/selfhost-deploy-remote.sh"
TMP_DIR="$(mktemp -d)"
RUN_ID="test-$$"
DEPLOY_TMP="/tmp/multica-deploy-${RUN_ID}"
FAKEBIN_DIR="${TMP_DIR}/fakebin"
LOG_FILE="${TMP_DIR}/commands.log"
MARKER_FILE="${TMP_DIR}/backup-ran"
cleanup() {
  rm -rf "${TMP_DIR}" "${DEPLOY_TMP}"
}
trap cleanup EXIT

mkdir -p "${FAKEBIN_DIR}" "${DEPLOY_TMP}/scripts"

cat > "${FAKEBIN_DIR}/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-u" ]]; then
  shift 2
fi
exec "$@"
EOF
chmod +x "${FAKEBIN_DIR}/sudo"

cat > "${FAKEBIN_DIR}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "\$*" >> "${LOG_FILE}"
exit 0
EOF
chmod +x "${FAKEBIN_DIR}/docker"

cat > "${FAKEBIN_DIR}/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "\$*" >> "${LOG_FILE}"
exit 0
EOF
chmod +x "${FAKEBIN_DIR}/curl"

git -C "${ROOT_DIR}" bundle create "${DEPLOY_TMP}/multica-deploy.bundle" HEAD >/dev/null

cat > "${DEPLOY_TMP}/scripts/selfhost-backup.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
touch "${MARKER_FILE}"
exit 99
EOF
chmod +x "${DEPLOY_TMP}/scripts/selfhost-backup.sh"

tar -czf "${DEPLOY_TMP}/multica-deploy-assets.tgz" -C "${DEPLOY_TMP}" multica-deploy.bundle scripts/selfhost-backup.sh

export PATH="${FAKEBIN_DIR}:${PATH}"
export DEPLOY_DIR="${TMP_DIR}/deploy-target"
export DEPLOY_APP_USER="$(id -un)"
export DEPLOY_RUN_ID="${RUN_ID}"
export DEPLOY_SHA="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
export DEPLOY_REPO="ninggc/multica"

bash "${SCRIPT_PATH}"

test -d "${DEPLOY_DIR}/.git"
test "$(git -C "${DEPLOY_DIR}" rev-parse HEAD)" = "${DEPLOY_SHA}"
test "$(git -C "${DEPLOY_DIR}" config --get remote.origin.url)" = "git@github.com:${DEPLOY_REPO}.git"
test ! -e "${MARKER_FILE}"
