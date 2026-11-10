package main

import rego.v1

# Checks on rendered manifests (kustomize build output), one document at a time.

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet"}

containers contains c if {
	input.kind in workload_kinds
	some c in input.spec.template.spec.containers
}

deny contains msg if {
	some c in containers
	not c.resources.requests.cpu
	msg := sprintf("%s/%s: container %s has no cpu request", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	some c in containers
	not c.resources.requests.memory
	msg := sprintf("%s/%s: container %s has no memory request", [input.kind, input.metadata.name, c.name])
}

# A memory limit is required, a cpu limit is not: cpu limits only add
# throttling, while an unbounded memory use takes the node's neighbours down.
deny contains msg if {
	some c in containers
	not c.resources.limits.memory
	msg := sprintf("%s/%s: container %s has no memory limit", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	some c in containers
	not c.readinessProbe
	msg := sprintf("%s/%s: container %s has no readinessProbe", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	some c in containers
	not c.livenessProbe
	msg := sprintf("%s/%s: container %s has no livenessProbe", [input.kind, input.metadata.name, c.name])
}

# A tag such as latest moves under Argo CD's feet, so Git would no longer say
# what runs. Digests are fine too.
deny contains msg if {
	some c in containers
	not pinned(c.image)
	msg := sprintf("%s/%s: image %s must have a fixed tag or digest", [input.kind, input.metadata.name, c.image])
}

pinned(image) if contains(image, "@sha256:")

pinned(image) if {
	parts := split(image, "/")
	last := parts[count(parts) - 1]
	tag_parts := split(last, ":")
	count(tag_parts) == 2
	tag_parts[1] != "latest"
}

deny contains msg if {
	some c in containers
	not c.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("%s/%s: container %s must set allowPrivilegeEscalation: false", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	some c in containers
	not c.securityContext.readOnlyRootFilesystem == true
	msg := sprintf("%s/%s: container %s must set readOnlyRootFilesystem: true", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	input.kind in workload_kinds
	not input.spec.template.spec.securityContext.runAsNonRoot == true
	msg := sprintf("%s/%s: pod securityContext must set runAsNonRoot: true", [input.kind, input.metadata.name])
}
