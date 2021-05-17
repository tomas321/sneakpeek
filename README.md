# sneakpeek

- spy on docker containers' files
- current supports overlay2 FS.
- utilizes the output of `docker inspect`

## Tools
### [sneakpeek.sh](./sneakpeek.sh)

#### `-t files` - view changed files (docker overlayFS merged\_dir)
- read JSON docker inspect output
- output all changed files in container

#### `-t merged_dir` - retrieve container merged\_dir
- usually used as an internal function
- returns the container merged dir

#### `-t fswatch` - setup fswatch
- setups fswatch systemd services for dynamically found containers in k8s cluster

#### `-t procmon` - setup for process monitoring for execsnoop
- creates eBPF maps for execsnoop namespace filtering (effectively monitor processes in a single container)

#### `-t tcptracer` - setup network connection monitoring for tcptracer

- creates eBPF maps for tcptracer namespace filtering (effectively monitor networking in a single container)

### [get\_all\_containers.sh](./get_all_containers.sh)

- get all container names in the whole cluster
- return lines of format: `NODE_IP,CONTAINER_ID`

### [get\_container\_ns.sh](./get_container_ns.sh)

- get the inode number of the /proc/PID/ns/mnt file
- it's effectively used for [BCC](https://github.com/iovisor/bcc) [execsnoop](https://github.com/iovisor/bcc/blob/master/tools/execsnoop.py) setup filtered with the container mount namespace

example usage for a sample `NODE_IP,CONTAINER_ID` output from [get\_all\_containers.sh](./get_all_containers.sh):
```bash
NODE_IP=10.0.0.3
CONTAINER_NAME=k8s_container_qwertyuiop
echo "inode number: $(./get_container_ns.sh -a $NODE_IP -n $CONTAINER_NAME)"
```

example output:
```
inode number: 24819530
```

### [bpftool\_map\_container\_ns.sh](./bpftool_map_container_ns.sh)
- implements the following functionality
- the retrieved inode number (see above) should be added to the eBPF map as so:
```bash
bpftool map create /sys/fs/bpf/mnt_ns_set type hash key 8 value 4 entries 128 name mnt_ns_set flags 0

INODE_NUMBER=24819530
FILE=/sys/fs/bpf/mnt_ns_set
if [ $(printf '\1' | od -dAn) -eq 1 ]; then
 HOST_ENDIAN_CMD=tac
else
  HOST_ENDIAN_CMD=cat
fi

NS_ID_HEX="$(printf '%016x' $INODE_NUMBER | sed 's/.\{2\}/&\n/g' | $HOST_ENDIAN_CMD)"
bpftool map update pinned $FILE key hex $NS_ID_HEX value hex 00 00 00 00 any
```

- finally run the execsnoop script to monitor the process in a single container:
```bash
execsnoop --mntnsmap /sys/fs/bpf/mnt_ns_set
```

# Author

Tomas Bellus
