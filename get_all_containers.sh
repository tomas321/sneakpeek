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
USAGE: $0\t[-c (docker | ...)] [-v]
"
HELP="$USAGE
\t\t-e,--exclude POD\texclude pod from sneakpeek. POD is the full pod name
\t\t-c,--engine ENGINE\tspecify the container engine (defaults to 'docker')
\t\t-v\t\tverbose setting
\t\t-h,--help\tprints this help

EXAMPLE:

exclude multiple pods:

\t $0 -e pod1-123 -e pod2-321
"

# required arguments
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
declare -a exclude_pods

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
            -e|--exclude)
                [[ ${REQUIRED_ARGS[-e]} -eq 1 ]] && REQUIRED_ARGS[-e]=0
                [[ $# -ge 2 ]] || fail "'-e': missing required parameter"
                shift

                # filter containers with excluded containers
                exclude_pods+=("$1")
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

# containers in the docker format 'CONTAINERNAME_PODNMAE,IP'
debug "retrieving all container/pod information via kubectl"
if [[ $container_engine == 'docker' ]]; then
    # the trimming is of container ID is specific to docker - ID begins with 'docker://' -> [9:21]
    containers=$(kubectl get pods -o json | jq -r '.items[] | "\(.spec.containers[].name)_\(.metadata.name),\(.status.hostIP),\(.status.containerStatuses[] | select(.ready == true and .started == true) | .containerID | .[9:21])"')
else
    fail "container engine '$container_engine': not supported"
fi

debug "printing nodeIP-container mapping"
for c in $containers; do
    exclude=0
    pod=$(echo $c | cut -d, -f1 | cut -d_ -f2)
    for exclude_pod in $exclude_pods; do
        if [[ "$exclude_pod" == "$pod" ]]; then
            exclude=1 && break
        fi
    done
    [ $exclude == 1 ] || echo $c | cut -d, -f2-
done

exit 0
