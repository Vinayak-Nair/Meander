#!/usr/bin/env bash
# Creates a self-signed "Meander Dev" code-signing certificate in the login
# keychain (idempotent). Signing every local build with this stable identity
# keeps the macOS Accessibility grant (needed for the global push-to-talk hotkey)
# from being invalidated on every rebuild — which is what happens with the
# default ad-hoc signing, since each ad-hoc build gets a fresh signature.
#
# No Apple Developer account needed. The cert is untrusted as a root, which is
# fine: codesign still signs with it, and the app's designated requirement
# becomes cert-based (stable) instead of build-hash-based.
#
# Run once:  ./scripts/setup-dev-cert.sh
set -euo pipefail

CERT_NAME="Meander Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$CERT_NAME\""; then
  echo "Code-signing identity '$CERT_NAME' already exists. Nothing to do."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# LibreSSL (system openssl) writes a PKCS#12 that `security` can import. Use a
# non-empty password to avoid an empty-password MAC-verification quirk.
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.conf" 2>/dev/null

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:meander -name "$CERT_NAME" 2>/dev/null

# -A lets codesign use the key without a per-build keychain prompt.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P meander -A -T /usr/bin/codesign

echo "Created code-signing identity '$CERT_NAME'."
echo "Now build with scripts/dev-run.sh and grant Accessibility to Meander once."
