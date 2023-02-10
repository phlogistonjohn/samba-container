
include Makefile

H=a34c560605b

CUSTOM_SERVER_BUILD_ARGS = \
	--build-arg=INSTALL_PACKAGES_FROM=custom-repo \
	--build-arg=INSTALL_CUSTOM_REPO=http://localhost:8000/jjm-hack-$H.repo \
	--net=host

.PHONY: a
a:
	$(MAKE) -f custom.mk b
	podman push quay.io/samba.org/samba-server:dev  docker://localhost:5555/samba.org/samba-server:vfs

.PHONY: b
b: repo-file build-custom-server

.PHONY: repo-file
repo-file:
	(cd ~/tmp/samba.out.d/jjm-hack1/RPMS/ && createrepo . && cp jjm-hack1.repo jjm-hack-$H.repo)

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

.PHONY: rpms
rpms:
	python ./images/fromsource/build.py -c a.yaml
