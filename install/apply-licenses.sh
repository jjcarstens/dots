#!/usr/bin/env sh
# Apply paid-app licenses from 1Password (personal account). Run after the apps
# are installed. Safe to re-run. Native sh, macOS-only.
#
#   sh install/apply-licenses.sh
#
# Requires the 1Password CLI signed into the personal account, with license items
# in the Private vault. If op isn't available it skips cleanly.
set -eu

ACCOUNT="my.1password.com"      # personal 1Password account
VAULT="Private"

MISE="$(command -v mise || true)"
op_read() {   # op_read "op://Vault/Item/field"
  if command -v op >/dev/null 2>&1; then
    op read "$1" --account "$ACCOUNT" 2>/dev/null
  elif [ -n "$MISE" ]; then
    "$MISE" exec -- op read "$1" --account "$ACCOUNT" 2>/dev/null
  fi
}

if [ -z "$(op_read "op://$VAULT/Alfred/license key" || true)" ]; then
  echo "1Password CLI not available/signed in — skipping license apply."
  echo "Sign into the '$ACCOUNT' account, then re-run: sh install/apply-licenses.sh"
  exit 0
fi

# --- Alfred: license is a file — opening it makes Alfred import & activate ----
if [ -d "/Applications/Alfred 5.app" ] || [ -d "/Applications/Alfred.app" ]; then
  tmp="$(mktemp -t alfred).alfredlicense"
  op_read "op://$VAULT/Alfred/license key" > "$tmp" || true
  if [ -s "$tmp" ]; then
    open "$tmp" && echo "Alfred: license opened — Alfred will import and activate it."
  fi
  rm -f "$tmp"
else
  echo "Alfred: not installed yet — re-run after installing it."
fi

# --- Rocket: no programmatic activation; print the key for a one-time paste ---
rocket_key="$(op_read "op://$VAULT/Rocket/license key" || true)"
if [ -n "$rocket_key" ]; then
  echo "Rocket: open Preferences > License and paste this key (one-time):"
  echo "    $rocket_key"
fi

# --- Dash: account-based online activation (no key) --------------------------
echo "Dash: open the app, then click 'Activate Dash on this machine' from your"
echo "      Kapeli account (https://kapeli.com/account) — no key needed."
