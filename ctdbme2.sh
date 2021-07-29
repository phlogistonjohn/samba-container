#!/bin/bash
# Its a hack. A hack for testing.

set -e

STAGE="$1"
# Change this to something that works for you.
LDIR="${HOME}/tmp/_ctdb"

# Cusomizations
img=quay.io/samba.org/samba-server:ctdb
cfg=("--config=/usr/local/share/sambacc/examples/ctdb.json"
     "--id=demo")
podextraopts=()
ctrextraopts=()

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

ctdb_pod() {
    local nn="${1}"
    local pubport=$((nn+4450))
    local name="ctdb${nn}"
    local cdelay=$nn
    local sdelay=$((nn+10))

    ec podman pod create \
        --hostname="ctdbme-${name}" \
        --name="${name}" \
        --share=pid,uts,net \
        --publish="${pubport}:445" \
        --network=ctdb \
        "${podextraopts[@]}"
    ec podman pod start "${name}"
    ec podman run \
        --rm \
        --pod="${name}" \
        --name="${name}-ctdb-set-node" \
        --cap-add=SYS_PTRACE \
        --cap-add=IPC_LOCK \
        -v "$LDIR/shared":/var/lib/ctdb/shared \
        "$img" "${cfg[@]}" \
        --debug-delay=1 \
        ctdb-set-node \
        --hostname="ctdbme-${name}" --node-number="$((nn-1))"
    ec podman run \
        --rm \
        --pod="${name}" \
        --name="${name}-ctdb-set-node" \
        --cap-add=SYS_PTRACE \
        --cap-add=IPC_LOCK \
        -v "$LDIR/shared":/var/lib/ctdb/shared \
        "$img" "${cfg[@]}" \
        --debug-delay=1 \
        ctdb-must-have-node \
        --node-number="$((nn-1))"
    ec podman run \
        --detach \
        --pod="${name}" \
        --name="${name}-node-mon" \
        --cap-add=SYS_PTRACE \
        --cap-add=IPC_LOCK \
        -v "$LDIR/samba/data/${nn}":/var/lib/samba \
        -v "$LDIR/conf":/etc/ctdb/ \
        -v "$LDIR/shared":/var/lib/ctdb/shared \
        -v "$LDIR/p/${nn}":/var/lib/ctdb/persistent \
        -v "$LDIR/s/${nn}":/var/run/ctdb \
        -v "$LDIR/v/${nn}":/var/lib/ctdb/volatile \
        "$img" "${cfg[@]}" \
        ctdb-manage-nodes --node-number="$((nn-1))"
    ec podman run \
        --detach \
        --pod="${name}" \
        --name="${name}-ctdb" \
        --cap-add=SYS_PTRACE \
        --cap-add=IPC_LOCK \
        -v "$LDIR/samba/data/${nn}":/var/lib/samba \
        -v "$LDIR/conf":/etc/ctdb/ \
        -v "$LDIR/shared":/var/lib/ctdb/shared \
        -v "$LDIR/p/${nn}":/var/lib/ctdb/persistent \
        -v "$LDIR/s/${nn}":/var/run/ctdb \
        -v "$LDIR/v/${nn}":/var/lib/ctdb/volatile \
        "$img" "${cfg[@]}" \
        --debug-delay "${cdelay}" run ctdbd \
        --setup=smb_ctdb --setup=ctdb_config --setup=ctdb_etc --setup=ctdb_nodes
    ec podman run \
        --detach \
        --pod="${name}" \
        --name="${name}-smb" \
        --cap-add=SYS_PTRACE \
        --cap-add=IPC_LOCK \
        -v "$LDIR/samba/data/${nn}":/var/lib/samba \
        -v "$LDIR/conf":/etc/ctdb/ \
        -v "$LDIR/shared":/var/lib/ctdb/shared \
        -v "$LDIR/p/${nn}":/var/lib/ctdb/persistent \
        -v "$LDIR/s/${nn}":/var/run/ctdb \
        -v "$LDIR/v/${nn}":/var/lib/ctdb/volatile \
        -v "$LDIR/share_data":/share:z \
        "${ctrextraopts[@]}" \
        "$img" "${cfg[@]}" \
        --debug-delay "${sdelay}" --samba-debug=10 \
        run smbd --setup=users --setup=smb_ctdb 
}

stage cleanup
always ec podman kill ctdb1-smb
always ec podman kill ctdb2-smb
always ec podman kill ctdb3-smb
always ec podman kill ctdb1-ctdb
always ec podman kill ctdb2-ctdb
always ec podman kill ctdb3-ctdb
always ec podman kill ctdb1-node-mon
always ec podman kill ctdb2-node-mon
always ec podman kill ctdb3-node-mon
always ec podman pod kill ctdb1
always ec podman pod kill ctdb2
always ec podman pod kill ctdb3
always ec podman pod rm ctdb1
always ec podman pod rm ctdb2
always ec podman pod rm ctdb3
retrying 5 podman network rm ctdb
endstage cleanup

stage dirprep
mkdir -p "$LDIR"
mkdir -p "$LDIR/samba/conf" "$LDIR/samba/data" "$LDIR/share"
mkdir -p "$LDIR/conf" "$LDIR/shared"
mkdir -p "$LDIR/samba/data/1" "$LDIR/samba/data/2" "$LDIR/samba/data/3"
mkdir -p "$LDIR/p/1" "$LDIR/p/2" "$LDIR/p/3"
mkdir -p "$LDIR/v/1" "$LDIR/v/2" "$LDIR/v/3"
mkdir -p "$LDIR/s/1" "$LDIR/s/2" "$LDIR/s/3"
mkdir -p "$LDIR/share_data"
chmod 0777 "${LDIR}"/share_data
endstage dirprep

stage prep
ec podman network create ctdb
endstage prep

stage setup
ec podman run \
    --rm \
    -v "$LDIR/samba/data/1":/var/lib/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/1":/var/lib/ctdb/persistent \
    "$img" \
    "${cfg[@]}" init
ec podman run \
    --rm \
    -v "$LDIR/samba/data/1":/var/lib/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/1":/var/lib/ctdb/persistent \
    "$img" \
    "${cfg[@]}" import
ec podman run \
    --rm \
    -v "$LDIR/samba/data/1":/var/lib/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/1":/var/lib/ctdb/persistent \
    "$img" \
    "${cfg[@]}" import-users

always ec podman run \
    --rm \
    -v "$LDIR/samba/data/1":/var/lib/samba \
    -v "$LDIR/conf":/etc/ctdb/ \
    -v "$LDIR/shared":/var/lib/ctdb/shared \
    -v "$LDIR/p/1":/var/lib/ctdb/persistent \
    "$img" \
    "${cfg[@]}" ctdb-migrate --dest-dir=/var/lib/ctdb/persistent
endstage setup


stage run
ctdb_pod 1
ctdb_pod 2
ctdb_pod 3
endstage run

stage logs
podman logs -f ctdb{1,2,3}-ctdb |& tee x
endstage logs
