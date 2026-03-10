#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${ROOT_DIR}/.venv"

if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi

if ! "${VENV_DIR}/bin/python" -c "import mcp" >/dev/null 2>&1; then
  "${VENV_DIR}/bin/pip" install -r "${ROOT_DIR}/requirements.txt"
fi

if [[ -z "${APPFOLLOW_API_TOKEN:-}" ]]; then
  echo "APPFOLLOW_API_TOKEN is required."
  echo "Example:"
  echo "  APPFOLLOW_API_TOKEN=... ${ROOT_DIR}/run.sh"
  exit 1
fi

exec "${VENV_DIR}/bin/python" "${ROOT_DIR}/server.py"
