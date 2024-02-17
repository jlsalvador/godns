.DEFAULT_GOAL := build

GO_SOURCE=$(wildcard *.go)
# Binary name
BINARY=godns
BUILD_DIR ?= $(shell pwd)/build
# Compilation flags
ifeq (${VERSION},)
VERSION := $(strip $(shell git describe --tags --match='v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || printf v0.0.1))
endif
PLATFORMS=linux/amd64 linux/arm64 linux/arm darwin/amd64 darwin/arm64 windows/amd64 windows/arm64
LDFLAGS+=\
	-X main.Version=${VERSION}
	-extldflags=-static -w -s

# Binary names
BINARIES=${BINARY} $(foreach PLATFORM,${PLATFORMS},${BINARY}_${VERSION}_$(subst /,_,${PLATFORM})$(if $(findstring windows,${PLATFORM}),.exe,))
BINARIES_TAR_GZ_COMPRESSED=$(foreach BIN,${BINARIES},$(subst .exe,,${BIN}).tar.gz)

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
GOCYCLO ?= $(LOCALBIN)/gocyclo
MISSPELL ?= $(LOCALBIN)/misspell

## Tool Versions
GOCYCLO_VERSION ?= latest
MISSPELL_VERSION ?= latest


##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


##@ Test Dependencies

.PHONY: gocyclo
gocyclo: $(GOCYCLO) ## Download gocyclo locally if necessary.
$(GOCYCLO): $(LOCALBIN)
	test -s $(LOCALBIN)/gocyclo || GOBIN=$(LOCALBIN) go install github.com/fzipp/gocyclo/cmd/gocyclo@$(GOCYCLO_VERSION)

.PHONY: misspell
misspell: $(MISSPELL) ## Download misspell locally if necessary.
$(MISSPELL): $(LOCALBIN)
	test -s $(LOCALBIN)/misspell || GOBIN=$(LOCALBIN) go install github.com/client9/misspell/cmd/misspell@$(MISSPELL_VERSION)


##@ Test

.PHONY: cyclo
test-cyclo: gocyclo ## Run gocyclo against code.
	$(GOCYCLO) -over 15 .

.PHONY: test-misspell
test-misspell: misspell ## Run misspell against code.
	$(MISSPELL) -error cmd internal pkg LICENSE Makefile README.md

.PHONY: test-go
test-go: internal/server/out ## Test code.
	go test ./... -cover

.PHONY: test
test: test-cyclo test-misspell test-go ## Execute all tests.


##@ Build

internal/server/out:
	npm ci --prefix ./web
	npm run build --prefix ./web
	go generate ./...

${BINARIES}: ${GO_SOURCE} internal/server/out
	GO111MODULE=on GOOS=$(word 3,$(subst _, ,$@)) GOARCH=$(subst .exe,,$(word 4,$(subst _, ,$@))) go build \
		-ldflags="${LDFLAGS}" \
		-trimpath \
		-o $@ \
		cmd/godns/godns.go

${BINARIES_TAR_GZ_COMPRESSED}:
	make $(subst .tar.gz,,$@)$(if $(findstring windows,$@),.exe,)
	tar \
		--transform='s/godns.*$(if $(findstring windows,$@),\.exe,)/${BINARY}$(if $(findstring windows,$@),.exe,)/' \
		--show-stored-names \
		-czvf $@ \
		$(subst .tar.gz,,$@)$(if $(findstring windows,$@),.exe,) README.md LICENSE

.PHONY: build
build: godns ## Builds the project

.PHONY: install
install: build ## Installs our project: copies binaries
	GO111MODULE=on go install


##@ Cleaning targets

clean: ## Cleans our projects: deletes binaries
	go clean
	rm -rf ${BINARIES} ${BINARIES_TAR_GZ_COMPRESSED} web/out internal/server/out


##@ Release

.PHONY: image
image: ## Generate container image releases
	# Build docker image
	go clean
	$(foreach TAG,${VERSION} latest, docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t timothyye/godns:${TAG} . --push)

.PHONY: release
release: | clean ${BINARIES_TAR_GZ_COMPRESSED} image ## Publish releases
