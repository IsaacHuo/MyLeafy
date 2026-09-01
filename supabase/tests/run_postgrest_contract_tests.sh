#!/usr/bin/env bash

set -euo pipefail

eval "$(supabase status -o env)"

assert_rpc_resolves() {
  local rpc_name="$1"
  local payload="$2"
  local result
  local response
  local code
  local status

  result="$(
    curl --silent --show-error \
      --connect-timeout 5 \
      --max-time 15 \
      --request POST \
      "${API_URL}/rest/v1/rpc/${rpc_name}" \
      --header "apikey: ${ANON_KEY}" \
      --header "Authorization: Bearer ${ANON_KEY}" \
      --header "Content-Type: application/json" \
      --data "${payload}" \
      --write-out $'\n%{http_code}'
  )"
  status="${result##*$'\n'}"
  response="${result%$'\n'*}"
  code="$(jq -r '.code // empty' <<<"${response}")"

  if [[ "${status}" != "401" || "${code}" != "42501" ]]; then
    printf 'RPC %s returned HTTP %s for payload %s: %s\n' \
      "${rpc_name}" "${status}" "${payload}" "${response}" >&2
    return 1
  fi
}

assert_rpc_resolves \
  "create_community_comment_v2" \
  '{"p_id":"00000000-0000-0000-0000-000000000001","p_post_id":"00000000-0000-0000-0000-000000000002","p_body":"contract probe","p_is_anonymous":false,"p_request_id":"00000000-0000-0000-0000-000000000003"}'

assert_rpc_resolves \
  "create_community_comment_v2" \
  '{"p_id":"00000000-0000-0000-0000-000000000001","p_post_id":"00000000-0000-0000-0000-000000000002","p_body":"contract probe","p_parent_comment_id":null,"p_reply_to_comment_id":null,"p_is_anonymous":false,"p_request_id":"00000000-0000-0000-0000-000000000003"}'

assert_rpc_resolves \
  "create_community_post_v4" \
  '{"p_id":"00000000-0000-0000-0000-000000000001","p_title":"contract probe","p_body":"contract probe","p_is_anonymous":false,"p_image_count":0,"p_attachment_count":0,"p_request_id":"00000000-0000-0000-0000-000000000003"}'

assert_rpc_resolves \
  "create_community_post_v4" \
  '{"p_id":"00000000-0000-0000-0000-000000000001","p_title":"contract probe","p_body":"contract probe","p_category":null,"p_is_anonymous":false,"p_image_count":0,"p_attachment_count":0,"p_request_id":"00000000-0000-0000-0000-000000000003"}'

assert_rpc_resolves "admin_daily_counts" '{}'
assert_rpc_resolves "admin_activity_heatmap" '{}'
assert_rpc_resolves "admin_category_mix" '{}'
assert_rpc_resolves "admin_top_content" '{}'
