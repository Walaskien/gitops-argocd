package main

import rego.v1

# Checks on the Argo CD objects in bootstrap/ and argocd/.

app_spec := input.spec if input.kind == "Application"

app_spec := input.spec.template.spec if input.kind == "ApplicationSet"

deny contains msg if {
	app_spec
	not app_spec.syncPolicy.automated.prune == true
	msg := sprintf("%s/%s: automated sync must set prune: true", [input.kind, input.metadata.name])
}

deny contains msg if {
	app_spec
	not app_spec.syncPolicy.automated.selfHeal == true
	msg := sprintf("%s/%s: automated sync must set selfHeal: true", [input.kind, input.metadata.name])
}

# The default project allows any repo and any destination.
deny contains msg if {
	app_spec
	app_spec.project == "default"
	msg := sprintf("%s/%s: use a dedicated AppProject, not default", [input.kind, input.metadata.name])
}

# HEAD follows whatever the remote default branch is. Name the branch.
deny contains msg if {
	app_spec
	not app_spec.source.targetRevision
	msg := sprintf("%s/%s: source.targetRevision must be set", [input.kind, input.metadata.name])
}

deny contains msg if {
	app_spec
	app_spec.source.targetRevision == "HEAD"
	msg := sprintf("%s/%s: source.targetRevision must name a branch or tag, not HEAD", [input.kind, input.metadata.name])
}

deny contains msg if {
	input.kind == "AppProject"
	some repo in input.spec.sourceRepos
	repo == "*"
	msg := sprintf("AppProject/%s: sourceRepos must not contain *", [input.metadata.name])
}

deny contains msg if {
	input.kind == "AppProject"
	some d in input.spec.destinations
	d.namespace == "*"
	msg := sprintf("AppProject/%s: destinations must not allow every namespace", [input.metadata.name])
}
