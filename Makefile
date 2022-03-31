# Copyright 2019 The Kubernetes Authors.
# SPDX-License-Identifier: Apache-2.0
#
# Makefile for kustomize CLI and API.

MODULES := '"cmd/config" "api/" "kustomize/" "kyaml/"'
LATEST_V4_RELEASE=v4.5.4

SHELL := /usr/bin/env bash
GOOS = $(shell go env GOOS)
GOARCH = $(shell go env GOARCH)
MYGOBIN = $(shell go env GOBIN)
ifeq ($(MYGOBIN),)
MYGOBIN = $(shell go env GOPATH)/bin
endif
export PATH := $(MYGOBIN):$(PATH)

# Provide defaults for REPO_OWNER and REPO_NAME if not present.
# Typically these values would be provided by Prow.
ifndef REPO_OWNER
REPO_OWNER := "kubernetes-sigs"
endif

ifndef REPO_NAME
REPO_NAME := "kustomize"
endif


.PHONY: all
all: install-tools verify-kustomize


# --- Plugins ---
include Makefile-plugins.mk


# --- Tool management ---
include Makefile-tools.mk

.PHONY: install-tools
install-tools: \
	install-local-tools \
	install-out-of-tree-tools

.PHONY: uninstall-tools
uninstall-tools: \
	uninstall-local-tools \
	uninstall-out-of-tree-tools

.PHONY: install-local-tools
install-local-tools: \
	$(MYGOBIN)/gorepomod \
	$(MYGOBIN)/k8scopy \
	$(MYGOBIN)/pluginator

.PHONY: uninstall-local-tools
uninstall-local-tools:
	rm -f $(MYGOBIN)/gorepomod
	rm -f $(MYGOBIN)/k8scopy
	rm -f $(MYGOBIN)/pluginator

# Build from local source.
$(MYGOBIN)/gorepomod:
	cd cmd/gorepomod; \
	go install .

# Build from local source.
$(MYGOBIN)/k8scopy:
	cd cmd/k8scopy; \
	go install .

# Build from local source.
$(MYGOBIN)/pluginator:
	cd cmd/pluginator; \
	go install .


# --- Build targets ---

# Build from local source.
$(MYGOBIN)/kustomize: build-kustomize-api
	cd kustomize; \
	go install .

kustomize: $(MYGOBIN)/kustomize

# Used to add non-default compilation flags when experimenting with
# plugin-to-api compatibility checks.
.PHONY: build-kustomize-api
build-kustomize-api: $(builtinplugins)
	cd api; go build ./...

.PHONY: generate-kustomize-api
generate-kustomize-api: $(MYGOBIN)/k8scopy
	cd api; go generate ./...


# --- Verification targets ---
.PHONY: verify-kustomize
verify-kustomize: \
	lint \
	license \
	test-unit-kustomize-all \
	test-unit-cmd-all \
	test-go-mod \
	test-examples-kustomize-against-HEAD \
	test-examples-kustomize-against-v4-release

# The following target referenced by a file in
# https://github.com/kubernetes/test-infra/tree/master/config/jobs/kubernetes-sigs/kustomize
.PHONY: prow-presubmit-check
prow-presubmit-check: \
	all

.PHONY: license
license: $(MYGOBIN)/addlicense
	$(MYGOBIN)/addlicense \
	  -y 2022 \
	  -c "The Kubernetes Authors." \
	  -f LICENSE_TEMPLATE \
	  -ignore "kyaml/internal/forked/github.com/**/*" \
	  -ignore "site/**/*" \
	  -ignore "**/*.md" \
	  -ignore "**/*.json" \
	  -ignore "**/*.yml" \
	  -ignore "**/*.yaml" \
	  -v \
	  .

.PHONY: lint
lint: $(MYGOBIN)/golangci-lint $(builtinplugins)
	cd api; $(MYGOBIN)/golangci-lint-kustomize \
	  -c ../.golangci.yml \
	  --path-prefix api \
	  run ./...
	cd kustomize; $(MYGOBIN)/golangci-lint-kustomize \
	  -c ../.golangci.yml \
	  --path-prefix kustomize \
	  run ./...
	cd cmd/pluginator; $(MYGOBIN)/golangci-lint-kustomize \
	  -c ../../.golangci.yml \
	  --path-prefix cmd/pluginator \
	  run ./...

.PHONY: test-unit-kustomize-api
test-unit-kustomize-api: build-kustomize-api
	cd api; go test ./...  -ldflags "-X sigs.k8s.io/kustomize/api/provenance.version=v444.333.222"
	cd api/krusty; OPENAPI_TEST=true go test -run TestCustomOpenAPIFieldFromComponentWithOverlays

.PHONY: test-unit-kustomize-plugins
test-unit-kustomize-plugins:
	./hack/testUnitKustomizePlugins.sh

.PHONY: test-unit-kustomize-cli
test-unit-kustomize-cli:
	cd kustomize; go test ./...

.PHONY: test-unit-kustomize-all
test-unit-kustomize-all: \
	test-unit-kustomize-api \
	test-unit-kustomize-cli \
	test-unit-kustomize-plugins

test-unit-cmd-all:
	./hack/kyaml-pre-commit.sh

test-go-mod:
	./hack/check-go-mod.sh

.PHONY:
verify-kustomize-e2e: $(MYGOBIN)/mdrip $(MYGOBIN)/kind
	( \
		set -e; \
		/bin/rm -f $(MYGOBIN)/kustomize; \
		echo "Installing kustomize from ."; \
		cd kustomize; go install .; cd ..; \
		./hack/testExamplesE2EAgainstKustomize.sh .; \
	)

.PHONY:
test-examples-kustomize-against-HEAD: $(MYGOBIN)/kustomize $(MYGOBIN)/mdrip
	./hack/testExamplesAgainstKustomize.sh HEAD

.PHONY:
test-examples-kustomize-against-v4-release: $(MYGOBIN)/mdrip
	./hack/testExamplesAgainstKustomize.sh v4@$(LATEST_V4_RELEASE)


# --- Cleanup targets ---
.PHONY: clean
clean: clean-kustomize-external-go-plugin uninstall-tools
	go clean --cache
	rm -f $(builtinplugins)
	rm -f $(MYGOBIN)/kustomize

# Nuke the site from orbit.  It's the only way to be sure.
.PHONY: nuke
nuke: clean
	go clean --modcache
