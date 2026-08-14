#!/usr/bin/env sh
# One-time setup the dotfiles assume but don't create. Idempotent.
#   - ~/repos: used by .zshrc (repos(), `compctl -W ~/repos`, logsincelast).
#   - github.com host key: .ssh/config sets StrictHostKeyChecking yes, so the
#     first git@github.com clone fails unless the key is already trusted.
set -eu

mkdir -p "$HOME/repos"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if ! ssh-keygen -F github.com >/dev/null 2>&1; then
  ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
  chmod 600 "$HOME/.ssh/known_hosts" 2>/dev/null || true
fi
