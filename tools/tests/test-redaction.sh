#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/agy-termux-lib.sh"

tmp_in="$(mktemp /data/data/com.termux/files/usr/tmp/redact.in.XXXXXX)"
tmp_out="$(mktemp /data/data/com.termux/files/usr/tmp/redact.out.XXXXXX)"
trap 'rm -f "$tmp_in" "$tmp_out"' EXIT

cat >"$tmp_in" <<'EOF'
Authorization: Bearer SECRET_TOKEN
Cookie: sid=abc
Set-Cookie: auth=xyz
https://example.com/callback?code=AAA&state=BBB
access_token=tok123 refresh_token=ref123 id_token=id123
user_email=test@example.com
EOF

agy_redact_file "$tmp_in" "$tmp_out"

if grep -Eq 'SECRET_TOKEN|sid=abc|auth=xyz|code=AAA|state=BBB|tok123|ref123|id123|test@example.com' "$tmp_out"; then
    echo "redaction test failed"
    exit 1
fi

echo "redaction test ok"
