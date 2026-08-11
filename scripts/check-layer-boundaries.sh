#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

fail_if_found() {
  local description="$1"
  shift
  local matches
  matches="$(rg -n "$@" || true)"
  if [[ -n "${matches}" ]]; then
    printf '%s\n%s\n' "${description}" "${matches}" >&2
    return 1
  fi
}

fail_if_found \
  "iOS App 源码仍包含 macOS/AppKit 平台路径：" \
  'import AppKit|canImport\(AppKit\)|#if os\(macOS\)|#elseif os\(macOS\)|#if os\(iOS\)' \
  leafy

fail_if_found \
  "Community Presentation 仍直连 Supabase/Data 单例：" \
  '^import Supabase|CommunityService\.shared|LeafySupabase' \
  leafy/Features/Community/Presentation

fail_if_found \
  "Domain 仍依赖 SwiftUI：" \
  '^import SwiftUI' \
  leafy/Features/*/Domain

fail_if_found \
  "已删除的 legacy 符号仍有引用：" \
  'LeafyPlatformImage|legacyNativeTabShell|AppFontSizePreference|CustomCountdownStore|UIConstants|publish_community_post_v1' \
  leafy leafyTests supabase/functions

printf '%s\n' "Layer boundary checks passed."
