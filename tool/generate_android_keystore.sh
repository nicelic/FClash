#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-keystore.jks}"
alias_name="${2:-fclash}"

if [ -e "$out_file" ]; then
  echo "Refusing to overwrite existing keystore: $out_file" >&2
  exit 1
fi

read -r -s -p "Enter keystore password (min 6 chars): " store_pass
echo
read -r -s -p "Re-enter keystore password: " store_pass_confirm
echo
if [ "$store_pass" != "$store_pass_confirm" ] || [ "${#store_pass}" -lt 6 ]; then
  echo "Passwords did not match or were shorter than 6 characters." >&2
  exit 1
fi

keytool -genkeypair -v \
  -keystore "$out_file" \
  -storetype PKCS12 \
  -alias "$alias_name" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "$store_pass" \
  -keypass "$store_pass" \
  -dname "CN=FClash, O=nicelic, C=US"

encoded="$(base64 < "$out_file" | tr -d '\r\n')"

cat <<EOF

Configure these 4 GitHub repository Secrets (Settings -> Secrets and variables -> Actions):
  KEY_ALIAS=$alias_name
  STORE_PASSWORD=$store_pass
  KEY_PASSWORD=$store_pass
  KEYSTORE=$encoded
EOF
