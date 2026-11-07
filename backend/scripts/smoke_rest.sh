#!/usr/bin/env bash
# REST smoke test against a real Supabase API (local or hosted): sign in, register a device, write through api_apply_operations,
# replay, pull, revoke, and check that an unauthenticated caller is refused.
# Usage: SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_ANON_KEY=... OWNER_EMAIL=... OWNER_PASSWORD=... backend/scripts/smoke_rest.sh
# It creates one goal and soft-deletes it again, and leaves one revoked device row. The audit log keeps both.
# The owner must already have called api_claim_owner(). Prefer running it against local Supabase.
set -euo pipefail
: "${SUPABASE_URL:?set SUPABASE_URL}" "${SUPABASE_ANON_KEY:?set SUPABASE_ANON_KEY}" "${OWNER_EMAIL:?set OWNER_EMAIL}" "${OWNER_PASSWORD:?set OWNER_PASSWORD}"
PY="${PY:-$(command -v python3 || command -v python)}"
uuid() { "$PY" -c 'import uuid;print(uuid.uuid4())'; }
json() { "$PY" -c "import sys,json;d=json.load(sys.stdin);print($1)"; }
ok() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; exit 1; }
H=(-H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json")

code=$(curl -s -o /dev/null -w '%{http_code}' "$SUPABASE_URL/rest/v1/muscles?select=key&limit=1" "${H[@]}")
if [ "$code" = 401 ] || [ "$code" = 403 ]; then ok "unauthenticated read refused ($code)"; else fail "unauthenticated read returned $code"; fi

TOKEN=$(curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" "${H[@]}" -d "{\"email\":\"$OWNER_EMAIL\",\"password\":\"$OWNER_PASSWORD\"}" | json "d['access_token']") || fail "sign in (is the email provider enabled?)"
ok "owner signs in"
A=(-H "Authorization: Bearer $TOKEN")
rpc() { curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/$1" "${H[@]}" "${A[@]}" -d "$2"; }

n=$(curl -s "$SUPABASE_URL/rest/v1/muscles?select=key" "${H[@]}" "${A[@]}" | json "len(d)")
[ "$n" -ge 29 ] && ok "owner reads $n muscles" || fail "owner read returned $n rows (claim ownership first?)"

DEV=$(uuid); GID=$(uuid); OP=$(uuid)
rpc api_register_device "{\"p_device_id\":\"$DEV\",\"p_label\":\"smoke test\",\"p_platform\":\"mobile\"}" | json "d['data']['id']" >/dev/null && ok "device registered"

ops="[{\"op_id\":\"$OP\",\"seq\":1,\"entity\":\"goals\",\"action\":\"upsert\",\"record_id\":\"$GID\",\"payload\":{\"type\":\"strength\",\"title\":\"smoke test goal\"}}]"
r=$(rpc api_apply_operations "{\"p_device_id\":\"$DEV\",\"p_request_id\":\"$(uuid)\",\"p_operations\":$ops}" | json "d['data']['results'][0]['result']")
[ "$r" = applied ] && ok "write applied" || fail "write returned $r"
r=$(rpc api_apply_operations "{\"p_device_id\":\"$DEV\",\"p_request_id\":\"$(uuid)\",\"p_operations\":$ops}" | json "d['data']['results'][0]['result']")
[ "$r" = duplicate ] && ok "replay is a duplicate" || fail "replay returned $r"

r=$(rpc api_pull_changes "{\"p_device_id\":\"$DEV\",\"p_since_rev\":0,\"p_limit\":5}" | json "str(len(d['data']['rows']))+' '+str(d['data']['has_more'])")
[ "$r" = "5 True" ] && ok "pull pages (5 rows, more available)" || fail "pull returned: $r"

del="[{\"op_id\":\"$(uuid)\",\"seq\":1,\"entity\":\"goals\",\"action\":\"delete\",\"record_id\":\"$GID\"}]"
r=$(rpc api_apply_operations "{\"p_device_id\":\"$DEV\",\"p_request_id\":\"$(uuid)\",\"p_operations\":$del}" | json "d['data']['results'][0]['result']")
[ "$r" = applied ] && ok "test goal soft-deleted" || fail "delete returned $r"

rpc api_revoke_device "{\"p_device_id\":\"$DEV\"}" | json "d['data']['revoked_at'] is not None" | grep -q True && ok "device revoked" || fail "revoke"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/rpc/api_pull_changes" "${H[@]}" "${A[@]}" -d "{\"p_device_id\":\"$DEV\",\"p_since_rev\":0,\"p_limit\":5}")
[ "$code" = 403 ] && ok "revoked device refused (403)" || fail "revoked device got $code"
echo "ALL SMOKE CHECKS PASSED"
