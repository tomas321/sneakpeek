#!/bin/bash
#
# process docker inspect output
# REQUIRES: jq
#


# GLOBALS

USAGE="
USAGE: $0
       $0\t-f DOCKER_INSPECT_FILE -t (files | merged_dir) [--chroot]
       $0\t-a NODE_IP -n CONTAINER_NAME -t (files | merged_dir) [--chroot]
\t\t\t[-u SSH_USER]
\t\t\t[-c CONTAINER_ENGINE]
\t\t\t[-v]
"
HELP="$USAGE
\t\t\t-a,--node-addr\tIP or host of target k8s node
\t\t\t-c,--engine\tcontainer engine (defaults to 'docker')
\t\t\t-f,--file\tpath to docker inspect outpu JSON file
\t\t\t-n,--container-name\tfull container name on the target k8s node
\t\t\t-t,--type\ttype of processing to apply on the inspect file
\t\t\t   --chroot\tremoves the base dir to the container FS in the output
\t\t\t-u,--ssh-user\tssh user to k8s cluster node (defaults to 'vagrant')
\t\t\t-h,--help\tprints this help

Running sneakpeek without arguments, sets the dynamic mode. Gets all containers on remote k8s cluster.
"

# possible required arguments groups
POSSIBILITIES=('' '-f-t' '-a-n-t')

VERBOSE=0

# JQ queries

ID_QUERY=".[].Id"
DIFF_FS_QUERY=".[].GraphDriver.Data.UpperDir"
MERGED_FS_QUERY=".[].GraphDriver.Data.MergedDir"
MOUNTS_QUERY=".[].Mounts[] | select(.RW == true)"  # only RW mounts

# OPTION VARIABLES

t_chroot=0
k8s_ssh_user='vagrant'
k8s_container_engine='docker'
container_inspect_command="container_dynamic"

fail() {
    echo -e "error: $*" >&2
    echo -e "   $USAGE" >&2
    exit 1
}

warn() {
    echo -e "warning: $*" >&2
}

debug() {
    [[ $VERBOSE -eq 1 ]] && echo -e "DEBUG: $*" >&2
}

# usage: $0 ARG
mark_argument_as_read() {
    for pos in "${!POSSIBILITIES[@]}"; do
        POSSIBILITIES[$pos]=${POSSIBILITIES[$pos]/$1/}
    done
}

####################
## ARGUMENTS LOOP ##
####################
parse_args() {
    inspect_file=""

    while (( "$#" )); do
        case "$1" in
            -f|--file)
                mark_argument_as_read '-f'
                [[ $# -ge 2 ]] || fail "'-f': missing required parameter"
                [[ -e "$2" ]] || fail "'$2': file does not exist"
                shift

                inspect_file="$1"
                ;;
            -t|--type)
                mark_argument_as_read '-t'
                [[ $# -ge 2 ]] || fail "'-t': missing required parameter"
                shift

                case "$1" in
                    files)
                        t_inspect_type="files"  # only informative
                        container_inspect_command="container_changed_files"
                        ;;
                    merged_dir)
                        t_inspect_type="merged_dir"  # only informative
                        container_inspect_command="container_merged_dir"
                        ;;
                    *)
                        [[ $# -gt 0 ]] && fail "'-t': unknown parameter '$1'"
                        ;;
                esac
                debug "read -t options chroot=$t_chroot type=$t_inspect_type cmd=$container_inspect_command"
                ;;
            -a|--node-addr)
                mark_argument_as_read '-a'
                [[ $# -ge 2 ]] || fail "'-a': missing required parameter"
                # TODO: validate IP address/hostname
                shift

                k8s_node_addr="$1"
                ;;
            -n|--container-name)
                mark_argument_as_read '-n'
                [[ $# -ge 2 ]] || fail "'-n': missing required parameter"
                shift

                container_name="$1"
                ;;
            -u|--ssh-user)
                mark_argument_as_read '-u'
                [[ $# -ge 2 ]] || fail "'-u': missing required parameter"
                shift

                k8s_ssh_user="$1"
                ;;
            -c|--engine)
                mark_argument_as_read '-c'
                [[ $# -ge 2 ]] || fail "'-c': missing required parameter"
                shift

                case "$1" in
                    docker)
                        ;;
                    *)
                        [[ $# -gt 0 ]] && fail "'-t': unknown parameter '$1'"
                        ;;
                esac
                k8s_container_engine="$1"
                ;;
            --chroot)
                t_chroot=1
                ;;
            -v|--verbose)
                VERBOSE=1
                ;;
            --help|-h)
                echo -e "$HELP" && exit 0
                ;;
            *)
                [[ $# -gt 0 ]] && fail "unknown argument '$1'"
                ;;
        esac
        shift
    done
    debug "parsed all arguemnts"
}

parse_args "$@"

# check if all required arguments were passed
check_required_args() {
    for i in "${!POSSIBILITIES[@]}"; do
        pos=${POSSIBILITIES[$i]}
        [[ -z "$pos" ]] && return 0
    done

    fail "missing required argument(s)"
}

check_required_args

##########
## MAIN ##
##########

# list changed files from docker merged dir
container_changed_files() {
    debug "listing changed files: chroot=$t_chroot"
    if [ $inspect_file ]; then
        merged_dir=$(jq -r "$MERGED_FS_QUERY" "$inspect_file")
    else
        [[ $k8s_container_engine == 'docker' ]] && merged_dir=$(ssh -l $k8s_ssh_user $k8s_node_addr "sudo docker inspect $container_name" | jq -r "$MERGED_FS_QUERY")
    fi
    (( $t_chroot )) && ssh -l $k8s_ssh_user $k8s_node_addr "sudo find $merged_dir" | sed "s|$merged_dir||g"
    (( ! $t_chroot )) && ssh -l $k8s_ssh_user $k8s_node_addr "sudo find $merged_dir"
}

# return the container merged directory
container_merged_dir() {
    debug "returning container merged dir"
    if [ $inspect_file ]; then
        merged_dir=$(jq -r "$MERGED_FS_QUERY" "$inspect_file")
    else
        [[ $k8s_container_engine == 'docker' ]] && merged_dir=$(ssh -l $k8s_ssh_user $k8s_node_addr "sudo docker inspect $container_name" | jq -r "$MERGED_FS_QUERY")
    fi
    echo "$merged_dir" && exit 0
}

# dynamically setup fswatch for all containers on all k8s nodes
container_dynamic() {
    debug "retrieving all containers from k8s cluster"
    k8s_containers=$(./get_all_containers.sh -c $k8s_container_engine -u $k8s_ssh_user)

    services=()
    next_ip=""
    ip=""
    for line in $k8s_containers; do
        next_ip=$(echo $line | cut -d, -f1)

        if [[ -n $ip ]] && [[ "$ip" != "$next_ip" ]]; then
            debug "ssh: connecting to $ip"
            debug "starting ${services[*]}"
            ssh -l $k8s_ssh_user $ip "sudo systemctl daemon-reload"
            ssh -l $k8s_ssh_user $ip "sudo systemctl start ${services[*]}"
            services=()
        fi

        ip=$next_ip
        container_name="$(echo $line | cut -d, -f2)"
        k8s_node_addr=$ip
        merged_dir=$(container_merged_dir)
        services+=("fswatch@$merged_dir.service")
    done

    debug "ssh: connecting to $ip"
    ssh -l $k8s_ssh_user $ip "sudo systemctl daemon-reload"
    ssh -l $k8s_ssh_user $ip "sudo systemctl start ${services[*]}"
}


[ $container_inspect_command ] && eval "$container_inspect_command"

exit 0
