#!/bin/sh

set -ex

# UNUSED?    --pod-id-file=wbtest.id.txt \

sharedir=/home/jmulliga/tmp/smbtest1

if [ "$1" == "stop" ]; then
    podman pod stop wbtest
    podman pod rm wbtest
    rm -rf "${sharedir}"
    exit 0
fi


mkdir -p "${sharedir}"/private
mkdir -p "${sharedir}"/wbsockets
chmod 0755 "${sharedir}"/wbsockets

podman pod create \
    --dns=192.168.122.243 \
    --hostname=wbtest \
    --name=wbtest \
    --share=pid,uts,net \
    --publish=4550:445

podman pod start wbtest

podman container run \
    --pod=wbtest \
    --name=wbtest-wb \
    --detach \
    -v $PWD:/srv/scratch \
    -v "${sharedir}":/var/lib/samba:z \
    -v "${sharedir}/wbsockets":/run/samba/winbindd:z \
    -e SAMBA_CONTAINER_ID=wbtest \
    -e SAMBACC_CONFIG="/srv/scratch/demo.json" \
    --entrypoint samba-container \
    samba-container:jjm \
    --password=Passw0rd \
    run \
    --insecure-auto-join \
    winbindd
sleep 5s
podman container run \
    --pod=wbtest \
    --name=wbtest-smb \
    --detach \
    -v $PWD:/srv/scratch \
    -v "${sharedir}":/var/lib/samba:z \
    -v "${sharedir}/wbsockets":/run/samba/winbindd:z \
    --tmpfs=/scratch \
    -e SAMBA_CONTAINER_ID=wbtest \
    -e SAMBACC_CONFIG="/srv/scratch/demo.json" \
    --entrypoint bash \
    samba-container:jjm \
    -c 'samba-container init && sleep 33s && samba-container run --no-init smbd'
#    --entrypoint samba-container \
#    run \
#    smbd

