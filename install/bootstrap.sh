#!/usr/bin/env sh
# Fresh-machine bootstrap. Native POSIX sh — NO dependencies (this is what installs
# mise, which installs everything else). Safe to re-run: every step is idempotent.
#
#   sh -c "$(curl -fsLS https://raw.githubusercontent.com/jjcarstens/dots/main/install/bootstrap.sh)"
#
# Flow:
#   1. install mise (native curl)
#   2. mise installs chezmoi + 1Password CLI  (needed before apply: templates pull
#      the git signing key / licenses from 1Password)
#   3. chezmoi init --apply  -> dotfiles, app config, mise config, macOS defaults
#   4. mise install          -> runtimes + CLIs from the now-managed mise config
#   5. macOS only: Homebrew (last resort) for GUI casks in install/Brewfile
#   6. interactive review    -> optional App Store / manual apps (default: skip)
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

# --- 2. chezmoi + 1Password CLI (needed before apply) ------------------------
log "Installing chezmoi + 1Password CLI via mise"
"$MISE" use -g chezmoi@latest 1password-cli@latest

log "Checking 1Password CLI sign-in"
op_ready() { [ -n "$("$MISE" exec -- op account list 2>/dev/null)" ]; }
if ! op_ready; then
  cat <<'EOF'
    1Password CLI isn't available yet. In the 1Password app, enable
    Settings > Developer > "Integrate with 1Password CLI" and unlock it
    (needed for the git signing key + app licenses).
EOF
  while ! op_ready; do
    printf '    [w]ait & recheck, [c]ontinue without secrets, [a]bort? [w/c/a] '
    if [ ! -t 0 ]; then reply=a; echo "a (non-interactive)"; else read -r reply </dev/tty || reply=a; fi
    case "$reply" in
      c|C) export DOTS_SKIP_SECRETS=1
           echo "    Continuing without secrets — signing key + licenses skipped."
           echo "    Re-run this script once 1Password is set up to fill them in."
           break ;;
      a|A) exit 1 ;;
      *)   sleep 3 ;;
    esac
  done
  op_ready && log "1Password CLI now available"
fi

# --- 3. chezmoi init --apply -------------------------------------------------
log "Applying dotfiles with chezmoi ($REPO)"
"$MISE" exec -- chezmoi init --apply "$REPO"

# --- Private overlays (optional): work shell funcs + internal SSH hosts -------
# The public .zshrc / .ssh/config reference ~/.dots-private directly; without
# access this is skipped and the public config still works.
if [ ! -d "$HOME/.dots-private" ]; then
  log "Cloning private overlays (~/.dots-private)"
  git clone git@github.com:jjcarstens/dots-private.git "$HOME/.dots-private" 2>/dev/null \
    || echo "  private overlays skipped (no access) — public config still works."
fi

# --- 4. mise install (managed config) ----------------------------------------
log "Installing runtimes + CLIs from mise config"
"$MISE" install

# --- 5. Homebrew (macOS only, last resort for GUI casks) ---------------------
if [ "$OS" = "Darwin" ]; then
  if ! have brew; then
    log "Installing Homebrew (for GUI casks)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$p" ] && eval "$("$p" shellenv)" && break
    done
  fi

  SRC="$("$MISE" exec -- chezmoi source-path)"   # chezmoi source dir (holds install/)

  if have brew && [ -f "$SRC/install/Brewfile" ]; then
    log "Installing base apps via Homebrew"
    brew bundle --file "$SRC/install/Brewfile"
  fi

  # --- Apply paid-app licenses from 1Password (apps now installed) -----------
  if [ -f "$SRC/install/apply-licenses.sh" ]; then
    log "Applying app licenses from 1Password"
    sh "$SRC/install/apply-licenses.sh" || true
  fi

  # --- 6. interactive review: optional apps (default skip) -------------------
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

  log "Manual apps: see install/manual-apps.md (Tidewave + optional vendor tools)"
fi

log "Done. Open a new terminal (or 'exec zsh') to load the new shell config."
