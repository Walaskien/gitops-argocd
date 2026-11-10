package combined

import rego.v1

deployment := {"contents": {"kind": "Deployment", "metadata": {"name": "echo", "namespace": "echo-dev"}}}

default_deny := {"contents": {
	"kind": "NetworkPolicy",
	"metadata": {"name": "default-deny", "namespace": "echo-dev"},
	"spec": {"podSelector": {}, "policyTypes": ["Ingress", "Egress"]},
}}

allow_only := {"contents": {
	"kind": "NetworkPolicy",
	"metadata": {"name": "echo-from-namespace", "namespace": "echo-dev"},
	"spec": {
		"podSelector": {"matchLabels": {"app.kubernetes.io/name": "echo"}},
		"policyTypes": ["Ingress"],
		"ingress": [{"from": [{"podSelector": {}}]}],
	},
}}

test_default_deny_present_passes if {
	count(deny) == 0 with input as [deployment, default_deny, allow_only]
}

test_missing_default_deny_fails if {
	count(deny) == 1 with input as [deployment, allow_only]
}

test_default_deny_in_other_namespace_does_not_count if {
	other := {"contents": {
		"kind": "NetworkPolicy",
		"metadata": {"name": "default-deny", "namespace": "somewhere-else"},
		"spec": {"podSelector": {}, "policyTypes": ["Ingress"]},
	}}
	count(deny) == 1 with input as [deployment, other]
}
