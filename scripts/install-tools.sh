#!/usr/bin/env bash
# Installs the validation tools into a directory (linux amd64, used by CI).
# Versions and checksums are pinned here; the sums are the ones the projects
# publish next to their releases.
set -euo pipefail

dest=${1:?usage: install-tools.sh <dest-dir>}
mkdir -p "$dest"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() { # url sha256 member
  local url=$1 sum=$2 member=$3 file
  file=$tmp/$(basename "$url")
  curl -fsSL --retry 3 -o "$file" "$url"
  echo "$sum  $file" | sha256sum -c - >/dev/null
  tar -xzf "$file" -C "$dest" "$member"
}

fetch "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.8.3/kustomize_v5.8.3_linux_amd64.tar.gz" \
  cb9e31198d3f63b44848bd0afc4c8efc56e6cfef9c93a4a39a211940e6decd61 kustomize
fetch "https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz" \
  9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883 kubeconform
fetch "https://github.com/open-policy-agent/conftest/releases/download/v0.70.1/conftest_0.70.1_Linux_x86_64.tar.gz" \
  613d124b8f6c1f3cee890491f7ab19114cca5a2102ca47cb2e6c35b4c23f9c8a conftest

"$dest/kustomize" version
"$dest/kubeconform" -v
"$dest/conftest" --version
