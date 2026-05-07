#!/usr/bin/env bash
# Test complet d'un serveur TURN/STUN — utilise turnutils (paquet coturn)
# Usage : ./test-turn.sh <hostname> <username> <password>
# Exemple : ./test-turn.sh turn.salistar.com sallycards mypassword

set -euo pipefail

HOST="${1:-turn.salistar.com}"
USER="${2:-sallycards}"
PASS="${3:-}"

if [ -z "$PASS" ]; then
  echo "Usage: $0 <host> <user> <password>"
  exit 1
fi

echo "=== Test 1/4 : DNS ==="
if dig +short "$HOST" > /dev/null; then
  IP=$(dig +short "$HOST" | head -1)
  echo "OK : $HOST -> $IP"
else
  echo "FAIL : DNS introuvable pour $HOST"
  exit 1
fi

echo
echo "=== Test 2/4 : STUN binding (UDP 3478) ==="
if turnutils_stunclient -p 3478 "$HOST" 2>&1 | grep -q "Mapped address"; then
  echo "OK : STUN répond"
else
  echo "FAIL : STUN ne répond pas"
  exit 1
fi

echo
echo "=== Test 3/4 : TURN allocate (UDP) ==="
if echo "test" | turnutils_uclient -t -u "$USER" -w "$PASS" "$HOST" 2>&1 | grep -q "tot_send_msgs="; then
  echo "OK : TURN allocate UDP réussi"
else
  echo "WARN : TURN UDP allocate échoue — essayer TCP..."
fi

echo
echo "=== Test 4/4 : TURN allocate (TCP) ==="
if echo "test" | turnutils_uclient -t -y -u "$USER" -w "$PASS" "$HOST" 2>&1 | grep -q "tot_send_msgs="; then
  echo "OK : TURN allocate TCP réussi"
else
  echo "WARN : TURN TCP allocate échoue"
fi

echo
echo "=== Récapitulatif ==="
echo "Serveur : $HOST ($IP)"
echo "User    : $USER"
echo "Si tous les tests passent : ✓ TURN/STUN opérationnel"
echo "Si STUN OK mais TURN KO : vérifier credentials + plage 49152-65535"
