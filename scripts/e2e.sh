#!/usr/bin/env bash
# End-to-end check on a throwaway kind cluster (CI creates one, `make e2e`
# creates one locally). It installs Argo CD, applies bootstrap/ and then
# changes things in two places to see which side wins:
#
#   in Git       a version bump, a revert, a new file, a deleted file
#   in the cluster   a scale, a deleted object, a hand-edited image
#
# Git changes must arrive, cluster changes must be undone.
#
# Argo CD reads from a small git remote inside the cluster instead of GitHub,
# so the test needs no token and works for forks. The only thing rewritten in
# the tree under test is the repo URL.
set -euo pipefail
cd "$(dirname "$0")/.."

ARGOCD_VERSION=${ARGOCD_VERSION:-v3.3.18}
GIT_IMAGE=e2e-git-server:local
PUBLIC_REPO=https://github.com/Walaskien/gitops-argocd.git
CLUSTER_REPO=http://git-server.git.svc.cluster.local:8080/cgi-bin/git/repo.git
GIT_PORT=${GIT_PORT:-18080}
APP_PORT=${APP_PORT:-18081}

for tool in docker kind kubectl git curl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

# This script deletes and edits things on purpose, so it only talks to kind.
context=$(kubectl config current-context)
case $context in
  kind-*) cluster=${context#kind-} ;;
  *)
    echo "refusing to run against context '$context', only kind-* contexts are allowed" >&2
    exit 1
    ;;
esac

work=$(mktemp -d)
repo=$work/repo
git_pf_pid=

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

dump() {
  echo "---- state at failure ----"
  kubectl -n argocd get applications,applicationsets,appprojects -o wide || true
  kubectl -n argocd get applications -o yaml | grep -E '^    (name|message|phase|revision):|^      (message|phase):' || true
  kubectl get pods -A || true
  kubectl -n argocd logs statefulset/argocd-application-controller --tail=60 || true
  kubectl -n argocd logs deploy/argocd-repo-server --tail=60 || true
  kubectl -n argocd logs deploy/argocd-applicationset-controller --tail=40 || true
  kubectl -n git logs deploy/git-server --tail=30 || true
}

cleanup() {
  local rc=$?
  trap - EXIT
  if ((rc != 0)); then dump; fi
  if [[ -n $git_pf_pid ]]; then kill "$git_pf_pid" 2>/dev/null || true; fi
  rm -rf "$work"
  exit "$rc"
}
trap cleanup EXIT

# wait_for <description> <seconds> <command...>
wait_for() {
  local desc=$1 timeout=$2 deadline
  shift 2
  deadline=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      echo "timed out after ${timeout}s: $desc" >&2
      return 1
    fi
    sleep 3
  done
  echo "ok: $desc"
}

# check <description> <command...>
check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
  else
    echo "FAILED: $desc" >&2
    return 1
  fi
}

gone() { ! "$@"; }

# sed without -i, which differs between GNU and BSD
edit() { # file sed-expression
  sed "$2" "$1" >"$1.tmp"
  mv "$1.tmp" "$1"
}

app_status() { kubectl -n argocd get app "$1" -o jsonpath='{.status.sync.status}/{.status.health.status}'; }
app_ready() { [[ $(app_status "$1") == Synced/Healthy ]]; }
app_at() { # app revision
  [[ $(kubectl -n argocd get app "$1" -o jsonpath='{.status.sync.revision}') == "$2" ]] && app_ready "$1"
}
# The default poll is every few minutes. A hard refresh is what a webhook
# or the Refresh button does, so the test does not sit idle.
refresh() { kubectl -n argocd annotate app "$1" argocd.argoproj.io/refresh=hard --overwrite >/dev/null; }

ns_enforces_restricted() {
  [[ $(kubectl get ns "$1" -o go-template='{{index .metadata.labels "pod-security.kubernetes.io/enforce"}}') == restricted ]]
}
spec_replicas() { [[ $(kubectl -n "$1" get deploy echo -o jsonpath='{.spec.replicas}') == "$2" ]]; }
ready_replicas() { [[ $(kubectl -n "$1" get deploy echo -o jsonpath='{.status.readyReplicas}') == "$2" ]]; }
image_is() { [[ $(kubectl -n "$1" get deploy echo -o jsonpath='{.spec.template.spec.containers[0].image}') == "$2" ]]; }

# Ask the app what it serves, through a short-lived port-forward.
app_json() { # namespace
  local pid out
  kubectl -n "$1" port-forward svc/echo "$APP_PORT:80" >/dev/null 2>&1 &
  pid=$!
  out=$(curl -fsS --retry 10 --retry-delay 1 --retry-connrefused --max-time 3 "http://127.0.0.1:$APP_PORT/" 2>/dev/null) || out=
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  printf '%s' "$out"
}
serves() { # namespace field value
  local body
  body=$(app_json "$1")
  grep -q "\"$2\": \"$3\"" <<<"$body"
}

commit() { # message
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$1"
}
push() {
  git -C "$repo" push -q origin main
  git -C "$repo" rev-parse HEAD
}

log "context $context"

log "loading the git remote image into kind"
docker build -q -t "$GIT_IMAGE" e2e/git-server >/dev/null
kind load docker-image "$GIT_IMAGE" --name "$cluster"

log "installing Argo CD $ARGOCD_VERSION (core, no UI or API server)"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# server-side: the ApplicationSet CRD is too large for client-side apply
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/core-install.yaml" >/dev/null
kubectl wait --for=condition=Established --timeout=60s \
  crd/applications.argoproj.io crd/appprojects.argoproj.io crd/applicationsets.argoproj.io >/dev/null
kubectl -n argocd rollout status deploy/argocd-redis --timeout=240s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=240s
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=240s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=240s

log "starting the git remote"
kubectl apply -f e2e/git-server.yaml >/dev/null
kubectl -n git rollout status deploy/git-server --timeout=120s
kubectl -n git port-forward svc/git-server "$GIT_PORT:8080" >/dev/null 2>&1 &
git_pf_pid=$!

log "publishing the committed tree to it, with the repo URL rewritten"
mkdir "$repo"
git archive HEAD | tar -x -C "$repo"
for f in "$repo"/bootstrap/*.yaml "$repo"/argocd/*.yaml; do
  edit "$f" "s#$PUBLIC_REPO#$CLUSTER_REPO#g"
done
if grep -rq "$PUBLIC_REPO" "$repo/bootstrap" "$repo/argocd"; then
  echo "repo URL was not fully rewritten" >&2
  exit 1
fi
git -C "$repo" init -q -b main
git -C "$repo" config user.name e2e
git -C "$repo" config user.email e2e@example.invalid
git -C "$repo" remote add origin "http://127.0.0.1:$GIT_PORT/cgi-bin/git/repo.git"
wait_for "git remote answers" 60 git -C "$repo" ls-remote origin
commit "tree under test"
push >/dev/null

log "bootstrap: the one manual kubectl apply"
kubectl apply -f "$repo/bootstrap/" >/dev/null
wait_for "root is Synced and Healthy" 300 app_ready root
wait_for "echo-dev is Synced and Healthy" 300 app_ready echo-dev
wait_for "echo-prod-like is Synced and Healthy" 300 app_ready echo-prod-like

log "what Argo CD created"
check "namespace echo-dev enforces restricted pod security" ns_enforces_restricted echo-dev
check "namespace echo-prod-like enforces restricted pod security" ns_enforces_restricted echo-prod-like
check "echo-dev has 1 ready replica" ready_replicas echo-dev 1
check "echo-prod-like has 2 ready replicas" ready_replicas echo-prod-like 2
check "echo-prod-like has its PodDisruptionBudget" kubectl -n echo-prod-like get pdb echo
wait_for "dev serves its own version and message" 120 serves echo-dev version 6.9.1
check "dev message comes from the overlay" serves echo-dev message "hello from dev"
check "prod-like serves 6.8.0" serves echo-prod-like version 6.8.0

log "git change: dev moves to 6.10.0"
edit "$repo/apps/echo/overlays/dev/kustomization.yaml" 's/newTag: 6.9.1/newTag: 6.10.0/'
commit "dev: podinfo 6.10.0"
sha=$(push)
refresh echo-dev
wait_for "echo-dev is at $sha and healthy" 300 app_at echo-dev "$sha"
wait_for "dev now serves 6.10.0" 120 serves echo-dev version 6.10.0
check "prod-like was not touched" serves echo-prod-like version 6.8.0

log "rollback: git revert, nothing edited in the cluster"
git -C "$repo" revert --no-edit HEAD >/dev/null
sha=$(push)
refresh echo-dev
wait_for "echo-dev is at the revert commit $sha and healthy" 300 app_at echo-dev "$sha"
wait_for "dev serves 6.9.1 again" 120 serves echo-dev version 6.9.1

log "drift: manual changes are put back by selfHeal"
kubectl -n echo-dev scale deploy/echo --replicas=3 >/dev/null
wait_for "dev replicas are back to 1" 120 spec_replicas echo-dev 1

old_uid=$(kubectl -n echo-dev get networkpolicy default-deny -o jsonpath='{.metadata.uid}')
kubectl -n echo-dev delete networkpolicy default-deny >/dev/null
policy_recreated() {
  local uid
  uid=$(kubectl -n echo-dev get networkpolicy default-deny -o jsonpath='{.metadata.uid}') && [[ -n $uid && $uid != "$old_uid" ]]
}
wait_for "deleted NetworkPolicy is created again" 120 policy_recreated

kubectl -n echo-prod-like set image deploy/echo echo=ghcr.io/stefanprodan/podinfo:6.9.1 >/dev/null
wait_for "hand-edited image in prod-like is back to 6.8.0" 180 image_is echo-prod-like ghcr.io/stefanprodan/podinfo:6.8.0
wait_for "echo-dev is Synced and Healthy" 180 app_ready echo-dev
wait_for "echo-prod-like is Synced and Healthy" 180 app_ready echo-prod-like
wait_for "prod-like serves 6.8.0 after the rollout" 120 serves echo-prod-like version 6.8.0

log "prune: a file added to Git shows up, removed from Git it goes away"
cat >"$repo/apps/echo/overlays/dev/scratch.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: scratch
data:
  purpose: e2e prune check
YAML
awk '{print} /^resources:/{print "  - scratch.yaml"}' "$repo/apps/echo/overlays/dev/kustomization.yaml" >"$repo/kust.tmp"
mv "$repo/kust.tmp" "$repo/apps/echo/overlays/dev/kustomization.yaml"
commit "dev: add scratch configmap"
push >/dev/null
refresh echo-dev
wait_for "scratch ConfigMap is created" 180 kubectl -n echo-dev get configmap scratch

rm "$repo/apps/echo/overlays/dev/scratch.yaml"
grep -v 'scratch.yaml' "$repo/apps/echo/overlays/dev/kustomization.yaml" >"$repo/kust.tmp"
mv "$repo/kust.tmp" "$repo/apps/echo/overlays/dev/kustomization.yaml"
commit "dev: drop scratch configmap"
push >/dev/null
refresh echo-dev
wait_for "scratch ConfigMap is pruned" 180 gone kubectl -n echo-dev get configmap scratch
wait_for "echo-dev is Synced and Healthy" 180 app_ready echo-dev

log "final state"
kubectl -n argocd get applications
log "all e2e checks passed"
