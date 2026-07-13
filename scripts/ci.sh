#!/usr/bin/env bash
set -euo pipefail

windows_cwd() {
  if command -v wslpath >/dev/null 2>&1; then
    wslpath -w "${PWD}"
    return
  fi
  if pwd -W >/dev/null 2>&1; then
    pwd -W
    return
  fi
  pwd
}

is_wsl() {
  [[ -r /proc/version ]] && grep -qi microsoft /proc/version
}

run_forge() {
  if command -v "${FORGE_BIN:-forge}" >/dev/null 2>&1; then
    "${FORGE_BIN:-forge}" "$@"
    return
  fi
  if ! is_wsl && command -v forge.exe >/dev/null 2>&1; then
    forge.exe "$@"
    return
  fi
  if ! is_wsl && command -v powershell.exe >/dev/null 2>&1; then
    local cwd
    cwd="$(windows_cwd)"
    powershell.exe -NoProfile -Command "Set-Location -LiteralPath '${cwd}'; forge $*"
    return
  fi
  if is_wsl; then
    echo "native forge not found in WSL; install Foundry in WSL or use scripts/ci.ps1" >&2
  else
    echo "forge not found" >&2
  fi
  exit 127
}

run_forge fmt --check
run_forge build
run_forge test
