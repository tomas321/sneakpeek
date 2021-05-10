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
\t\t-c,--engine ENGINE\tspecify the container engine (defaults to 'docker')
\t\t-v\t\tverbose setting
\t\t-h,--help\tprints this help
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
if [[ $container_engine == 'docker' ]]; then
    # the trimming is of container ID is specific to docker - ID begins with 'docker://' -> [9:21]
    containers=$(kubectl get pods -o json | jq -r '.items[] | "\(.spec.containers[].name)_\(.metadata.name),\(.status.hostIP),\(.status.containerStatuses[] | select(.ready == true and .started == true) | .containerID | .[9:21])"')
else
    fail "container engine '$container_engine': not supported"
fi

for c in $containers; do
    echo $c | cut -d, -f2-
done

exit 0
