#!/bin/bash
#
# creates eBPF map if its missing
# converts the inode number to hex format
# updates the created map with the inode number
# run the execsnoop@mnt_ns_ABCD, where ABCD is the ID of the container and is extracted from the input argument FILE
#
# requires the template unit file `execsnoop@.service` || `tcptracer@.server` depending on the TYPE
#
# usage: $0 INODE FILE TYPE
#

# GLOBALS
USAGE="
USAGE:  $0
        $0 INODE FILE TYPE

\tINODE - positional argument OR as an ENV variable
\tFILE - positional argument OR as an ENV variable
\tTYPE - one of [execsnoop, tcptracer]

Either run with ENV variables or with positional arguments
"

# Process arguments
if [ $# -lt 1 ]; then
    if [ -z ${INODE+x} ]; then
        echo "ERROR: missing 'INODE' argument"; echo -e "$USAGE"; exit 1
    fi
    if [ -z ${FILE+x} ]; then
        echo "ERROR: missing 'FILE' argument"; echo -e "$USAGE"; exit 1
    fi
    if [ -z ${TYPE+x} ]; then
        echo "ERROR: missing 'TYPE' argument"; echo -e "$USAGE"; exit 1
    fi
elif [ $# -eq 3 ]; then
    INODE="$1"
    FILE="$2"
    TYPE="$3"
else
    echo "ERROR: bad number of arguments"; echo -e $USAGE""; exit 1
fi

NAME="${FILE##*/}"

function start_service() {
    [[ "$TYPE" == "execsnoop" ]] && echo "INFO: starting execsnoop@$NAME" >&2 && sudo systemctl start execsnoop@$NAME
    [[ "$TYPE" == "tcptracer" ]] && echo "INFO: starting tcptracer@$NAME" >&2 && sudo systemctl start tcptracer@$NAME
}

# choose endian
if [ $(printf '\1' | od -dAn) -eq 1 ]; then
    HOST_ENDIAN_CMD=tac
else
    HOST_ENDIAN_CMD=cat
fi
NS_ID_HEX="$(printf '%016x' $INODE | sed 's/.\{2\}/&\n/g' | $HOST_ENDIAN_CMD | tr '\n' ' ')"

# check if eBPF map already exists
bpfmap=$(sudo bpftool map show pinned $FILE 2>/dev/null)
if [ $? -eq 0 ]; then
    id=$(echo $bpfmap | cut -d: -f1)
    sudo bpftool map dump id $id | grep -q -i "$NS_ID_HEX"
    if [ $? -eq 0 ]; then
        echo "eBPF map already exists"
        start_service
        exit 0
    fi
else
    echo "creating eBPF map '$FILE'"
    sudo bpftool map create $FILE type hash key 8 value 4 entries 128 name $NAME flags 0
fi

echo "updating eBPF map with inode ID '$NS_ID_HEX'"
sudo bpftool map update pinned $FILE key hex $NS_ID_HEX value hex 00 00 00 00 any

# start a templated systemd service based on the TYPE
# essetially the systemd service runs a script
# e.g. '/usr/local/bin/execsnoop/execsnoop.sh NAME' using the name to construct the '--mntnsmap' option
# e.g. '/usr/local/bin/tcptracer/tcptracer.sh NAME' using the name to construct the '--mntnsmap' option
start_service
