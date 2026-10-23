#!/usr/bin/env bash
# Local and CI entrypoint. No Homebrew/global installation or build phase mutation.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=0.64.1
archive_sha256=0e5762a848d738602c7a983b26812031e634d85e357db070968b9c805f253eff

if [[ $(uname -s) != Darwin ]]; then
    echo 'Swift formatting requires macOS (the same pinned binary is used by iOS CI).' >&2
    exit 1
fi
cache_root="${XDG_CACHE_HOME:-${HOME}/Library/Caches}/MyLeafy/SwiftFormat/${version}"
binary="${cache_root}/swiftformat"
if [[ ! -x "$binary" ]]; then
    mkdir -p "$cache_root"
    download_dir=$(mktemp -d "${cache_root}/download.XXXXXX")
    trap 'rm -rf "$download_dir"' EXIT
    curl --fail --silent --show-error --location --retry 3 \
        "https://github.com/nicklockwood/SwiftFormat/releases/download/${version}/swiftformat.zip" \
        --output "${download_dir}/swiftformat.zip"
    printf '%s  %s\n' "$archive_sha256" "${download_dir}/swiftformat.zip" | shasum -a 256 --check
    unzip -q "${download_dir}/swiftformat.zip" -d "$download_dir"
    chmod +x "${download_dir}/swiftformat"
    mv "${download_dir}/swiftformat" "$binary"
    rm -rf "$download_dir"
    trap - EXIT
fi
if [[ $("$binary" --version) != "$version" ]]; then
    echo "Expected SwiftFormat ${version}; remove ${cache_root} and retry." >&2
    exit 1
fi

options=(--config "${repo_root}/.swiftformat" --cache ignore)
if [[ ${1:-} == --check ]]; then
    options+=(--lint)
    shift
fi
if [[ $# == 0 ]]; then
    set -- "${repo_root}/leafy" "${repo_root}/leafyTests" "${repo_root}/leafyWidget" \
        "${repo_root}/LeafyWidgetShared" "${repo_root}/LeafyShareExtension" \
        "${repo_root}/LeafyExternalImportShared"
fi
exec "$binary" "${options[@]}" "$@"
