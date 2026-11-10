# Rolling back

Roll back the way you roll forward: with Git.

```sh
git log --oneline -5 -- apps/echo/overlays/dev     # find the bad commit
git switch -c revert-dev-bump
git revert <sha>                                   # a merge commit needs -m 1
git push -u origin revert-dev-bump
```

Open the PR, let the checks run, merge. Argo CD applies the previous state
the same way it applied the change. Because the revert restores the old
`newTag` and the old ConfigMap content, the pods roll back too (the ConfigMap
name carries a hash of its content).

The e2e job does exactly this to dev: bumps the tag, then `git revert HEAD`,
and waits for the app to serve the old version again without anything being
touched in the cluster.

## Why not `argocd app rollback`

It is refused while automated sync is on, and if you switch automation off to
use it, the cluster no longer matches Git. Then the next person to read the
repo is looking at the wrong thing. A revert commit leaves the repo as the
record of what happened.

## When CI is the problem

If the checks are broken and the fix is urgent, someone with admin rights can
push the revert straight to `main`, assuming branch protection lets admins
through. Fix the checks afterwards. This is a deliberate exception and should
be rare enough to notice.
