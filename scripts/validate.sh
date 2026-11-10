#!/usr/bin/env bash
# The same checks run locally and in CI. Needs on PATH: yamllint, kustomize,
# kubeconform, conftest.
set -euo pipefail
cd "$(dirname "$0")/.."

K8S_VERSION=${K8S_VERSION:-1.34.0}
# The Argo CD CRD schemas are fetched, they are not part of the built-in set.
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Rendered output goes under the repo and not /tmp so a containerised
# kubeconform or conftest can read it through the same bind mount.
work=.tmp
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

step() { printf '\n== %s\n' "$*"; }

# The schema host drops a request now and then. Retry only for that, an
# invalid manifest should fail on the first run.
kubeconform_retry() {
  local out rc=0 attempt
  for attempt in 1 2 3; do
    if out=$(kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
      -schema-location default -schema-location "$CRD_SCHEMAS" "$@" 2>&1); then
      printf '%s\n' "$out"
      return 0
    else
      rc=$?
    fi
    printf '%s\n' "$out"
    grep -qE 'failed (parsing|downloading) schema|could not find schema|unexpected EOF|connection reset|timeout' <<<"$out" || return "$rc"
    echo "schema download problem, retrying ($attempt/3)" >&2
    sleep 3
  done
  return "$rc"
}

step "yamllint"
yamllint -s .

step "policy unit tests"
conftest verify --policy policy

step "argo cd objects: schema and policy"
kubeconform_retry bootstrap argocd
conftest test --policy policy bootstrap/*.yaml argocd/*.yaml

step "e2e helper manifests: schema"
kubeconform_retry e2e/git-server.yaml

# Rendering is what Argo CD applies, so the schema and policy checks run on
# the kustomize output and not on the source files.
for overlay in apps/echo/overlays/*/; do
  name=$(basename "$overlay")
  rendered=$work/$name.yaml
  step "overlay $name: build, schema, policy"
  kustomize build "$overlay" >"$rendered"
  kubeconform_retry "$rendered"
  conftest test --policy policy "$rendered"
  conftest test --policy policy --combine --namespace combined "$rendered"
done

step "base builds on its own"
kustomize build apps/echo/base >/dev/null

printf '\nall checks passed\n'
