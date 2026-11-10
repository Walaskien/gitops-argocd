package main

import rego.v1

app := {
	"kind": "Application",
	"metadata": {"name": "root"},
	"spec": {
		"project": "platform",
		"source": {"targetRevision": "main"},
		"syncPolicy": {"automated": {"prune": true, "selfHeal": true}},
	},
}

test_application_with_prune_and_selfheal_passes if {
	count(deny) == 0 with input as app
}

test_missing_selfheal_is_rejected if {
	a := object.union(app, {"spec": {"syncPolicy": {"automated": {"selfHeal": false}}}})
	count(deny) == 1 with input as a
}

test_manual_sync_is_rejected if {
	a := object.remove(app, ["spec"])
	b := object.union(a, {"spec": {"project": "platform", "source": {"targetRevision": "main"}}})
	count(deny) == 2 with input as b
}

test_default_project_is_rejected if {
	count(deny) == 1 with input as object.union(app, {"spec": {"project": "default"}})
}

test_head_is_rejected if {
	count(deny) == 1 with input as object.union(app, {"spec": {"source": {"targetRevision": "HEAD"}}})
}

test_applicationset_template_is_checked if {
	appset := {
		"kind": "ApplicationSet",
		"metadata": {"name": "echo"},
		"spec": {"template": {"spec": app.spec}},
	}
	count(deny) == 0 with input as appset
	bad := {
		"kind": "ApplicationSet",
		"metadata": {"name": "echo"},
		"spec": {"template": {"spec": object.union(app.spec, {"project": "default"})}},
	}
	count(deny) == 1 with input as bad
}

test_wildcard_project_is_rejected if {
	p := {
		"kind": "AppProject",
		"metadata": {"name": "loose"},
		"spec": {"sourceRepos": ["*"], "destinations": [{"namespace": "*"}]},
	}
	count(deny) == 2 with input as p
}
