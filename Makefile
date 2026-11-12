VENV    := $(CURDIR)/.venv/bin
CLUSTER ?= gitops-e2e
NODE    ?= kindest/node:v1.34.3

.PHONY: help venv validate e2e clean

help: ## list targets
	@grep -E '^[a-z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort

venv: ## python venv with yamllint
	python3 -m venv .venv
	$(VENV)/pip install yamllint==1.37.1

# kustomize, kubeconform and conftest must be on PATH, see scripts/install-tools.sh
validate: ## kustomize build, kubeconform, conftest policies
	PATH="$(VENV):$$PATH" scripts/validate.sh

# Own kubeconfig, so kind does not merge into ~/.kube/config or switch the
# current context of whatever cluster you work with.
e2e: export KUBECONFIG := $(CURDIR)/.kubeconfig
e2e: ## full kind run, needs kind and docker
	kind create cluster --name $(CLUSTER) --image $(NODE) --wait 120s
	scripts/e2e.sh; rc=$$?; kind delete cluster --name $(CLUSTER); exit $$rc

clean: ## remove .tmp and .kubeconfig
	rm -rf .tmp .kubeconfig
