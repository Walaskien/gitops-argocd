package main

import rego.v1

good := {
	"kind": "Deployment",
	"metadata": {"name": "echo"},
	"spec": {"template": {"spec": {
		"securityContext": {"runAsNonRoot": true},
		"containers": [{
			"name": "echo",
			"image": "ghcr.io/stefanprodan/podinfo:6.8.0",
			"readinessProbe": {"httpGet": {"path": "/readyz", "port": "http"}},
			"livenessProbe": {"httpGet": {"path": "/healthz", "port": "http"}},
			"resources": {
				"requests": {"cpu": "10m", "memory": "32Mi"},
				"limits": {"memory": "64Mi"},
			},
			"securityContext": {"allowPrivilegeEscalation": false, "readOnlyRootFilesystem": true},
		}],
	}}},
}

# Replace one container field on the good fixture. object.remove first,
# because object.union would merge nested objects instead of replacing them.
with_container(key, value) := object.union(good, {"spec": {"template": {"spec": {"containers": [c]}}}}) if {
	base := good.spec.template.spec.containers[0]
	c := object.union(object.remove(base, [key]), {key: value})
}

test_good_deployment_passes if {
	count(deny) == 0 with input as good
}

test_latest_tag_is_rejected if {
	deny["Deployment/echo: image ghcr.io/stefanprodan/podinfo:latest must have a fixed tag or digest"] with input as with_container("image", "ghcr.io/stefanprodan/podinfo:latest")
}

test_missing_tag_is_rejected if {
	count(deny) == 1 with input as with_container("image", "ghcr.io/stefanprodan/podinfo")
}

test_registry_port_is_not_mistaken_for_a_tag if {
	count(deny) == 1 with input as with_container("image", "localhost:5000/podinfo")
}

test_digest_is_accepted if {
	count(deny) == 0 with input as with_container("image", "ghcr.io/stefanprodan/podinfo@sha256:262578cde928d5c9eba3bce079976444f624c13ed0afb741d90d5423877496cb")
}

test_missing_memory_limit_is_rejected if {
	count(deny) == 1 with input as with_container("resources", {"requests": {"cpu": "10m", "memory": "32Mi"}})
}

test_missing_probes_are_rejected if {
	c := {k: v | some k, v in good.spec.template.spec.containers[0]; not k in {"readinessProbe", "livenessProbe"}}
	count(deny) == 2 with input as object.union(good, {"spec": {"template": {"spec": {"containers": [c]}}}})
}

test_writable_root_filesystem_is_rejected if {
	count(deny) == 1 with input as with_container("securityContext", {"allowPrivilegeEscalation": false})
}

test_pod_running_as_root_is_rejected if {
	pod := {"securityContext": {"runAsNonRoot": false}}
	count(deny) == 1 with input as object.union(good, {"spec": {"template": {"spec": pod}}})
}

test_other_kinds_are_ignored if {
	count(deny) == 0 with input as {"kind": "Service", "metadata": {"name": "echo"}}
}
