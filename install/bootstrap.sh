#!/usr/bin/env sh
# Fresh-machine bootstrap. Native POSIX sh — NO dependencies (this is what installs
# mise, which installs everything else). Safe to re-run: every step is idempotent.
#
#   sh -c "$(curl -fsLS https://raw.githubusercontent.com/jjcarstens/dots/main/install/bootstrap.sh)"
#
# Ordered so quick settings land before long downloads, and 1Password is only
# needed after its app is installed:
#   1. mise  2. chezmoi+op (ephemeral)  3. init --apply  4. clone private overlay
#   5. macos-defaults  6. packages (installs 1Password app)  7. op gate + re-apply
#   8. tools -> licenses -> optional apps
set -eu

REPO="jjcarstens/dots"
OS="$(uname -s)"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Ask a yes/no question; default NO. Returns 0 for yes. Non-interactive => no.
ask() {
  if [ ! -t 0 ]; then return 1; fi
  printf '    %s [y/N] ' "$1"
  read -r reply </dev/tty || return 1
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# --- 1. mise -----------------------------------------------------------------
if ! have mise; then
  log "Installing mise"
  curl -fsSL https://mise.run | sh
fi
# Put mise + its shims on PATH for the rest of this script.
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate sh 2>/dev/null || true)"
MISE="$(command -v mise || echo "$HOME/.local/bin/mise")"

# --- 2. chezmoi + 1Password CLI (ephemeral) ----------------------------------
# Run from mise WITHOUT `mise use -g` (which would pre-write/normalize
# ~/.config/mise/config.toml and trip chezmoi's "config has changed" prompt).
# The managed [tools] list installs them permanently on apply (step 3).
BOOT_TOOLS="chezmoi@latest 1password-cli@latest"
# shellcheck disable=SC2086  # intentional word-split of the two tool specs
mrun() { "$MISE" exec $BOOT_TOOLS -- "$@"; }
log "Preparing chezmoi + 1Password CLI via mise"
# shellcheck disable=SC2086
"$MISE" install $BOOT_TOOLS

op_ready() { [ -n "$(mrun op account list 2>/dev/null)" ]; }

# --- 3. chezmoi init --apply -------------------------------------------------
# Lays down dotfiles + mise config + run_once env (github.com host key, ~/repos).
# Skip secrets if op isn't ready yet; the signing key is filled in step 7.
log "Applying dotfiles with chezmoi ($REPO)"
if op_ready; then
  mrun chezmoi init --apply "$REPO"
else
  echo "    1Password not available yet — applying without secrets for now."
  DOTS_SKIP_SECRETS=1 mrun chezmoi init --apply "$REPO"
fi
SRC="$(mrun chezmoi source-path)"   # chezmoi source dir (holds install/)
"$MISE" trust -q "$HOME/.config/mise/config.toml" 2>/dev/null || true

# --- 4. Private overlays (optional): work shell funcs + internal SSH hosts -----
# Referenced directly by .zshrc / .ssh/config; skipped cleanly without access.
# Step 3 seeded github.com in known_hosts so this SSH clone won't stall.
if [ ! -d "$HOME/.dots-private" ]; then
  log "Cloning private overlays (~/.dots-private)"
  git clone git@github.com:jjcarstens/dots-private.git "$HOME/.dots-private" 2>/dev/null \
    || echo "  private overlays skipped (no access) — public config still works."
fi

# --- 5-8. mise bootstrap (managed config) ------------------------------------
# macOS: defaults -> packages (installs 1Password app) -> op gate -> tools.
# Linux: brew/cask entries are macOS-guarded, so just install the tools.
if [ "$OS" = "Darwin" ]; then
  # 5. Quick, no-download settings first.
  log "Applying macOS defaults (mise bootstrap)"
  "$MISE" bootstrap --only macos-defaults --yes

  # 6. Long download phase: brew formulae + casks (installs the 1Password app).
  log "Installing packages (mise bootstrap)"
  "$MISE" bootstrap --only packages --yes

  # 7. 1Password sign-in gate — the app exists now, so CLI integration can work.
  if ! op_ready; then
    log "Checking 1Password CLI sign-in"
    cat <<'EOF'
    In the 1Password app, enable Settings > Developer > "Integrate with
    1Password CLI" and unlock it (needed for the git signing key + app licenses).
EOF
    while ! op_ready; do
      printf '    [w]ait & recheck, [c]ontinue without secrets, [a]bort? [w/c/a] '
      if [ ! -t 0 ]; then reply=c; echo "c (non-interactive)"; else read -r reply </dev/tty || reply=c; fi
      case "$reply" in
        c|C) echo "    Continuing without secrets — signing key + licenses skipped."
             echo "    Re-run this script once 1Password is set up to fill them in."
             break ;;
        a|A) exit 1 ;;
        *)   sleep 3 ;;
      esac
    done
    # op online now -> re-apply to fill the signing key (no re-prompt; persisted).
    if op_ready; then
      log "1Password available — re-applying to fill the signing key"
      mrun chezmoi init --apply "$REPO"
    fi
  fi

  # 8. Runtimes + CLIs from [tools].
  log "Installing tools (mise bootstrap)"
  "$MISE" bootstrap --only tools --yes
else
  log "Installing runtimes + CLIs from mise config"
  "$MISE" install
fi

# --- macOS: paid-app licenses + optional apps --------------------------------
if [ "$OS" = "Darwin" ]; then
  # --- Apply paid-app licenses from 1Password (apps now installed) -----------
  if [ -f "$SRC/install/apply-licenses.sh" ]; then
    log "Applying app licenses from 1Password"
    sh "$SRC/install/apply-licenses.sh" || true
  fi

  # --- interactive review: optional apps (default skip) ----------------------
  MAS="$SRC/install/mas.txt"
  if [ -f "$MAS" ] && have mas; then
    log "Optional Mac App Store apps (default: skip)"
    while IFS= read -r line; do
      case "$line" in ''|\#*) continue ;; esac
      id="$(printf '%s' "$line" | awk '{print $1}')"
      name="$(printf '%s' "$line" | sed 's/^[0-9]*[[:space:]]*#[[:space:]]*//')"
      if ask "Install '$name'?"; then mas install "$id" || true; fi
    done < "$MAS"
  elif [ -f "$MAS" ]; then
    log "Skipping App Store review ('mas' not installed). See install/mas.txt"
  fi

  log "Manual apps: see install/manual-apps.md (Tidewave, Logi Options+, Wireshark + optional vendor tools)"
fi

log "Done. Open a new terminal (or 'exec zsh') to load the new shell config."
