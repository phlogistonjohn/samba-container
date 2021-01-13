#!/bin/sh

set -e

D=""

podman run $D -it --rm  \
    --name smbdemo1  -p 4451:445 \
    -v $PWD/demo.json:/etc/samba/container.json \
    --tmpfs=/share:rw,mode=1777 \
    samba-container:jjm

podman run $D -it --rm  \
    -e SAMBA_CONTAINER_ID=demo2 --name smbdemo2 -p 4452:445 \
    -v $PWD/demo.json:/etc/samba/container.json \
    --tmpfs=/mnt/one:rw,mode=1777 \
    --tmpfs=/mnt/two:rw,mode=1777  \
    samba-container:jjm

podman run $D -it --rm  \
    -e SAMBA_CONTAINER_ID=demo2 --name smbdemo3 -p 4453:445 \
    -v $PWD/demo.json:/etc/samba/container.json \
    -v $PWD/altusers.json:/etc/samba/users.json \
    --tmpfs=/mnt/one:rw,mode=1777 \
    --tmpfs=/mnt/two:rw,mode=1777  \
    samba-container:jjm
