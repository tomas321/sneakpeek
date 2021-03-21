#!/bin/bash
#
# creates eBPF map if its missing
# converts the inode number to hex format
# updates the created map with the inode number
#
# usage: $0 INODE
#

# GLOBALS
USAGE="
USAGE:  $0
        $0 INODE CONTAINER

\tINODE - positional argument OR as an ENV variable
\tCONTAINER - positional argument OR as an ENV variable

Either run with ENV variables or with positional arguments
"

# Process arguments
if [ $# -lt 1 ]; then
    if [ -z ${INODE+x} ]; then
        echo "ERROR: missing 'INODE' argument"; echo -e "$USAGE"; exit 1
    fi
    if [ -z ${CONTAINER+x} ]; then
        echo "ERROR: missing 'CONTAINER' argument"; echo -e "$USAGE"; exit 1
    fi
elif [ $# -eq 2 ]; then
    INODE=$1
    CONTAINER=$2
else
    echo "ERROR: bad number of arguments"; echo -e $USAGE""; exit 1
fi

NAME=mnt_ns_$CONTAINER
FILE=/sys/fs/bpf/$NAME

# choose endian
if [ $(printf '\1' | od -dAn) -eq 1 ]; then
    HOST_ENDIAN_CMD=tac
else
    HOST_ENDIAN_CMD=cat
fi
NS_ID_HEX="$(printf '%016x' $INODE | sed 's/.\{2\}/&\n/g' | $HOST_ENDIAN_CMD | tr '\n' ' ')"

# check if eBPF map already exists
bpfmap=$(sudo bpftool map show | grep $NAME)
if [ $? -eq 0 ]; then
    sudo bpftool map dump id $(echo "$bpfmap" | cut -d: -f1) | grep -q -i "$NS_ID_HEX"
    if [ $? -eq 0 ]; then
        echo "eBPF map already exists"; exit 0
    fi
else
    echo "creating eBPF map '$FILE'"
    sudo bpftool map create $FILE type hash key 8 value 4 entries 128 name $NAME flags 0
fi

echo "updating eBPF map with inode ID '$NS_ID_HEX'"
sudo bpftool map update pinned $FILE key hex $NS_ID_HEX value hex 00 00 00 00 any
