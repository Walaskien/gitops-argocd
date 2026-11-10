VENV    := $(CURDIR)/.venv/bin
CLUSTER ?= gitops-e2e
NODE    ?= kindest/node:v1.34.3

.PHONY: venv validate e2e clean

venv:
	python3 -m venv .venv
	$(VENV)/pip install yamllint==1.37.1

# kustomize, kubeconform and conftest must be on PATH, see scripts/install-tools.sh
validate:
	PATH="$(VENV):$$PATH" scripts/validate.sh

# Own kubeconfig, so kind does not merge into ~/.kube/config or switch the
# current context of whatever cluster you work with.
e2e: export KUBECONFIG := $(CURDIR)/.kubeconfig
e2e:
	kind create cluster --name $(CLUSTER) --image $(NODE) --wait 120s
	scripts/e2e.sh; rc=$$?; kind delete cluster --name $(CLUSTER); exit $$rc

clean:
	rm -rf .tmp .kubeconfig
