#!/bin/bash
#
# get all container names in the whole cluster.
# returns lines of format: NODE_IP,CONTAINER_ID
#
# requires:
#   - kubectl
#   - docker
#

# GLOBALS

USAGE="
USAGE: $0\t[-c (docker | ...)] [-u USER] [-v]
"
HELP="$USAGE
\t\t-c,--engine ENGINE\tspecify the container engine (defaults to 'docker')
\t\t-u,--ssh-user USER\tk8s node ssh user (defaults to 'vagrant')
\t\t-v\t\tverbose setting
\t\t-h,--help\tprints this help
"

# TODO # add all required arguments as so
declare -A REQUIRED_ARGS
# REQUIRED_ARGS[-a]=1

VERBOSE=0  # verbose logging

fail() {
    echo -e "error: $*" >&2
    echo -e "   $USAGE"
    exit 1
}

warn() {
    echo -e "warning: $*" >&2
}

debug() {
    [[ $VERBOSE -eq 1 ]] && echo -e "DEBUG: $*" >&2
}

# OPTION VARIABLES

container_engine="docker"
ssh_user="vagrant"

####################
## ARGUMENTS LOOP ##
####################
parse_args() {
    while (( "$#" )); do
        case "$1" in
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
                ssh_user="$2"
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

##########
## MAIN ##
##########
#
# Gather containers of each kubernetes pod
#
pods=$(kubectl get pods -o json | jq -r '.items[].metadata.name')
declare -A containers

for pod in $pods; do
    containers[$pod]=$(kubectl get pods -o json | jq -r '.items[] | select(.metadata.name == "'$pod'") | .spec.containers[].name')
done

#
# START: get docker container IDs
#
# usage: $0 NODE_IP [NODE_IP ...]
#
get_docker_container_names() {
    container_names=()

    for ip in "$@"; do
        debug "reading node($ip) containers"
        for pod in "${!containers[@]}"; do
            for pod_container in ${containers[$pod]}; do
                container_name="$pod_container""_""$pod"
                container_id=$(ssh "$ssh_user@$ip" "sudo docker ps --format '{{json .}}'" | grep "$container_name" | jq -r '.ID')
                [[ -n "$container_id" ]] && container_ids+=("$ip,$container_id")
            done
        done
    done

    echo "${container_ids[@]}"
}
#
# END: get docker container names
#

node_ips=$(kubectl get nodes -o json | jq -r '.items[].status.addresses[] | select(.type == "InternalIP") | .address')

if [[ $container_engine == 'docker' ]]; then
    containers=$(get_docker_container_names $node_ips)
fi

for c in $containers; do
    echo $c
done

exit 0
