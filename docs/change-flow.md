# Changing a version

The version of the app is one line per environment:

```
apps/echo/overlays/dev/kustomization.yaml         images[].newTag
apps/echo/overlays/prod-like/kustomization.yaml   images[].newTag
```

Nothing else in the repo decides what runs. The same goes for replicas and
the message: they live in the overlays too.

## The flow

1. Branch, change `newTag` in the dev overlay.
2. Open a PR. `validate` renders both overlays and checks schema and policy,
   `e2e` boots a kind cluster and runs the whole thing with your change.
3. Review, merge.
4. Argo CD notices the new commit (it polls every three minutes by default, a
   webhook makes it immediate) and syncs `echo-dev`.
5. Look at it: `kubectl -n argocd get app echo-dev` should show
   Synced and Healthy at the merge commit.
6. Second PR with the same tag for the prod-like overlay.

prod-like is meant to trail dev. If a version is not in dev yet, it does not
go into prod-like.

## What keeps people on this path

Three things, and only the last two are in this repo.

- Branch protection on `main`: pull request required, the three checks
  (`manifests`, `scripts-and-workflows`, `argocd-on-kind`) required, no
  force pushes, rules apply to admins as well. This is a GitHub setting, so
  it has to be switched on by whoever owns the repo.
- Argo CD is the only writer in the `echo-*` namespaces. If someone runs
  `kubectl edit` anyway, `selfHeal` reverts it, which the e2e job
  demonstrates with a scale, a deleted NetworkPolicy and an edited image.
- The root app runs in the `platform` project, which can only create Argo CD
  objects in the `argocd` namespace. A bad commit under `argocd/` cannot
  create workloads or cluster-wide resources through it.

## What is not covered

Nothing stops a PR from putting prod-like ahead of dev. The PR template asks
the question, a reviewer has to answer it.

There is no break-glass path. Pausing sync for an environment is a change to
the ApplicationSet, so it is a PR as well. For a real team that needs a
decision (who may push to `main` during an incident) before it is needed.
