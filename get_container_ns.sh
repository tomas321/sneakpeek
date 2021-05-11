#!/bin/bash
#
# get the mount namespace of the specified container
# return the process ns/mnt inode number i.e. using `stat -c '%i' /proc/$PID/ns/mnt`
#

# GLOBALS

USAGE="
USAGE: $0 -a NODE_HOST -n CONTAINER_NAME [-u SSH_USER] [-c (docker | ...)] [-v]
"
HELP="$USAGE
\t\t-a,--node HOST\t\tk8s node reachable ip or host
\t\t-c,--engine ENGINE\tspecify the container engine (defaults to 'docker')
\t\t-n,--name CONTAINER\tname of the container to inspect
\t\t-u,--ssh-user USER\tk8s node ssh user (defaults to 'vagrant')
\t\t-v\t\t\tverbose setting
\t\t-h,--help\t\tprints this help
"

declare -A REQUIRED_ARGS
REQUIRED_ARGS[-a]=1
REQUIRED_ARGS[-n]=1

VERBOSE=0  # verbose logging

fail() {
    echo -e "error: $*"
    echo -e "   $USAGE"
    exit 1
}

warn() {
    echo -e "warning: $*"
}

debug() {
    [[ $VERBOSE -eq 1 ]] && echo -e "DEBUG: $*"
}

# OPTION VARIABLES

container_engine="docker"
ssh_user="vagrant"

# TODO # change the ARGUMENTS LOOP
####################
## ARGUMENTS LOOP ##
####################
parse_args() {
    argvs=($@)

    while (( "$#" )); do
        case "$1" in
            -a|--node)
                [[ ${REQUIRED_ARGS[-a]} -eq 1 ]] && REQUIRED_ARGS[-a]=0
                [[ $# -ge 2 ]] || fail "'-a': missing required parameter"
                k8s_node_host="$2"
                shift
                ;;
            -n|--name)
                [[ ${REQUIRED_ARGS[-n]} -eq 1 ]] && REQUIRED_ARGS[-n]=0
                [[ $# -ge 2 ]] || fail "'-n': missing required parameter"
                container_name="$2"
                shift
                ;;
            -c|--engine)
                [[ ${REQUIRED_ARGS[-c]} -eq 1 ]] && REQUIRED_ARGS[-c]=0
                [[ $# -ge 2 ]] || fail "'-c': missing required parameter"
                shift

                case "$1" in
                    docker)
                        ;;
                    *)
                        [[ $# -gt 0 ]] && fail "'-c': unknown container engine '$1'"
                        ;;
                esac
                container_engine="$1"
                ;;
            -u|--ssh-user)
                [[ ${REQUIRED_ARGS[-u]} -eq 1 ]] && REQUIRED_ARGS[-u]=0
                [[ $# -ge 2 ]] || fail "'-u': missing required parameter"

                shift
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
for arg in "${!REQUIRED_ARGS[@]}"; do
    [[ ${REQUIRED_ARGS[$arg]} -eq 1 ]] && fail "missing required argument '$arg'"
done

# debug "-a is '$k8s_node_host'"
# debug "-n is '$container_name'"

##########
## MAIN ##
##########

NS=$(ssh $ssh_user@$k8s_node_host CONTAINER=$container_name 'bash -s' <<-"ENDSSH"
    pid=$(sudo docker inspect $CONTAINER | jq -r '.[0].State.Pid');
    echo $(sudo stat -Lc '%i' /proc/$pid/ns/mnt)
ENDSSH
)

echo $NS

exit 0
