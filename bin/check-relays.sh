#!/usr/bin/env bash
# Vérifie et relance les relais socat si nécessaire.
# Usage : bash bin/check-relays.sh

set -euo pipefail

RELAYS=(
  "4873:verdaccio:4873"
  "2222:ssh-target:22"
  "3001:ssh-target:3000"
)

relay_ok() {
  local port=$1
  pgrep -f "socat TCP-LISTEN:${port}" > /dev/null 2>&1
}

for relay in "${RELAYS[@]}"; do
  local_port="${relay%%:*}"
  target="${relay#*:}"

  if relay_ok "$local_port"; then
    echo "✓ socat :${local_port} → ${target} (actif)"
  else
    echo "✗ socat :${local_port} → ${target} (absent) → relance..."
    nohup socat "TCP-LISTEN:${local_port},fork,reuseaddr" "TCP:${target}" > /dev/null 2>&1 &
    echo "  ↳ relancé (PID $!)"
  fi
done

echo ""
echo "Vérification Verdaccio..."
if curl -sf http://localhost:4873/-/ping > /dev/null 2>&1; then
  echo "✓ Verdaccio opérationnel (http://localhost:4873)"
else
  echo "✗ Verdaccio inaccessible même après relance du relay"
  exit 1
fi
