#!/bin/bash
# Its a hack. A hack for testing.

set -e

STAGE="$1"
# Change this to something that works for you.
LDIR="/home/jmulliga/tmp/_ctdb"

always() {
    if ! "$@"; then
        echo "--> ignoring error running" "$@"
    fi
    return 0
}

retrying() {
    local count="$1"
    local i=0
    shift
    while [ "$i" -lt "$count" ]; do
        if "$@"; then
            return 0
        fi
        echo "--> ignoring error running" "$@"
        sleep 0.5
        i=$((i+1))
    done
}

ec() {
    echo "==>" "$@"
    "$@"
}

stage() {
    echo "[[[ start: $1 ]]]"
}

endstage() {
    echo "[[[ end: $1 ]]]"
    if [ "$STAGE" = "$1" ]; then
        exit 0
    fi
}

stage cleanup
always podman kill ctdb1
always podman kill ctdb2
always podman kill ctdb3
retrying 5 podman network rm ctdb
endstage cleanup

stage dirprep
mkdir -p "$LDIR"
mkdir -p "$LDIR/samba/conf" "$LDIR/samba/data"
mkdir -p "$LDIR/conf" "$LDIR/shared"
mkdir -p "$LDIR/p/1" "$LDIR/p/2" "$LDIR/p/3"

ln -sf "/usr/local/share/sambacc/examples/minimal.json" \
    "$LDIR/samba/conf/container.json"

cat >"$LDIR/samba/conf/smb.conf" <<EOF
[global]
include = registry
EOF
cat >"$LDIR/conf/ctdb.conf" <<EOF
[logging]
log level = DEBUG

[cluster]
recovery lock = /var/lib/ctdb/shared/RECOVERY

[legacy]
realtime scheduling = false
script log level = DEBUG
EOF
cat >"$LDIR/conf/nodes" <<EOF
10.88.4.2
10.88.4.3
10.88.4.4
EOF
cat >"$LDIR/conf/notify.sh" <<EOF
#!/bin/sh

echo OH HI "$@"
EOF
chmod ugo+x "$LDIR/conf/notify.sh"

cp /etc/ctdb/functions "$LDIR/conf/functions"
mkdir -p "$LDIR/conf/events/legacy"
ln -sf "/usr/share/ctdb/events/legacy/00.ctdb.script" \
    "$LDIR/conf/events/legacy/00.ctdb.script"
endstage dirprep

stage prep
ec podman network create ctdb
endstage prep

stage setup
ec podman run \
    --rm \
    -v "$LDIR/samba/data":/var/lib/samba \
    -v "$LDIR/samba/conf":/etc/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/1":/var/lib/ctdb/persistent \
    quay.io/samba.org/samba-server:ctdb \
    --id demo init
ec podman run \
    --rm \
    -v "$LDIR/samba/data":/var/lib/samba \
    -v "$LDIR/samba/conf":/etc/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/1":/var/lib/ctdb/persistent \
    quay.io/samba.org/samba-server:ctdb \
    --id demo import

always ec podman run \
    --rm \
    -v "$LDIR/samba/data":/var/lib/samba \
    -v "$LDIR/samba/conf":/etc/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/1":/var/lib/ctdb/persistent \
    quay.io/samba.org/samba-server:ctdb \
    --id demo ctdb-migrate --dest-dir=/var/lib/ctdb/persistent
endstage setup


stage run
cat >"$LDIR/samba/conf/smb.conf" <<EOF
[global]
clustering =yes
ctdb:registry.tdb = yes
include = registry
EOF
ec podman run \
    --rm \
    --detach \
    --cap-add=SYS_PTRACE \
    --cap-add=IPC_LOCK \
    --name ctdb1 \
    --network=ctdb \
    -p 4379 \
    -v "$LDIR/samba/data":/var/lib/samba \
    -v "$LDIR/samba/conf":/etc/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/1":/var/lib/ctdb/persistent \
    --init \
    quay.io/samba.org/samba-server:ctdb \
    --debug-delay 1 --id demo run ctdbd --no-init
ec podman run \
    --rm \
    --detach \
    --cap-add=SYS_PTRACE \
    --cap-add=IPC_LOCK \
    --name ctdb2 \
    --network=ctdb \
    -p 4379 \
    -v "$LDIR/samba/data":/var/lib/samba \
    -v "$LDIR/samba/conf":/etc/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/2":/var/lib/ctdb/persistent \
    --init \
    quay.io/samba.org/samba-server:ctdb \
    --debug-delay 2 --id demo run ctdbd --no-init
ec podman run \
    --rm \
    --detach \
    --cap-add=SYS_PTRACE \
    --cap-add=IPC_LOCK \
    --name ctdb3 \
    --network=ctdb \
    -p 4379 \
    -v "$LDIR/samba/data":/var/lib/samba \
    -v "$LDIR/samba/conf":/etc/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/3":/var/lib/ctdb/persistent \
    --init \
    quay.io/samba.org/samba-server:ctdb \
    --debug-delay 3 --id demo run ctdbd --no-init
endstage run

stage logs
podman logs -f ctdb1 ctdb2 |& tee x
endstage logs
