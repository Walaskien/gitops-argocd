package combined

import rego.v1

# Needs --combine: this one looks across all documents of a rendered overlay.
# Every namespace that runs a workload must also carry a policy that selects
# all pods and has no allow rules, otherwise the app-specific allow policy
# would be the only thing between the pods and the rest of the cluster.

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet"}

docs := [d.contents | some d in input]

namespaces_with_workloads contains ns if {
	some d in docs
	d.kind in workload_kinds
	ns := d.metadata.namespace
}

default_deny_namespaces contains ns if {
	some d in docs
	d.kind == "NetworkPolicy"
	count(d.spec.podSelector) == 0
	"Ingress" in d.spec.policyTypes
	not d.spec.ingress
	ns := d.metadata.namespace
}

deny contains msg if {
	some ns in namespaces_with_workloads
	not ns in default_deny_namespaces
	msg := sprintf("namespace %s runs workloads but has no default-deny ingress NetworkPolicy", [ns])
}
