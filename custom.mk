
include Makefile

CUSTOM_SERVER_BUILD_ARGS = \
	--build-arg=INSTALL_PACKAGES_FROM=custom-repo \
	--build-arg=INSTALL_CUSTOM_REPO=http://localhost:8000/jjm-hack1.repo \
	--net=host

.PHONY: build-custom-server
build-custom-server:
	$(MAKE) img-build \
		BUILD_ARGS="$(CUSTOM_SERVER_BUILD_ARGS)"  \
		EXTRA_BUILD_ARGS="$(EXTRA_BUILD_ARGS)" \
		SHORT_NAME=samba-server:dev \
		REPO_NAME=quay.io/samba.org/samba-server:dev \
		SRC_FILE=$(SERVER_SRC_FILE) \
		DIR=$(SERVER_DIR) \
		BUILDFILE=.custom.build

