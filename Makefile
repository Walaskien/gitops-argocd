VENV := $(CURDIR)/.venv/bin

.PHONY: venv validate clean

venv:
	python3 -m venv .venv
	$(VENV)/pip install yamllint==1.37.1

# kustomize, kubeconform and conftest must be on PATH, see scripts/install-tools.sh
validate:
	PATH="$(VENV):$$PATH" scripts/validate.sh

clean:
	rm -rf .tmp .kubeconfig
