#!/bin/bash
#
# process docker inspect output
# REQUIRES: jq
#


# GLOBALS

USAGE="
USAGE: $0\t-f DOCKER_INSPECT_FILE -t (files | ...) [--chroot]
\t\t\t[-v]
"
HELP="$USAGE
\t\t\t-f,--file\tpath to docker inspect outpu JSON file
\t\t\t-t,--type\ttype of processing to apply on the inspect file
\t\t\t    --chroot\tremoves the base dir to the container FS in the output
\t\t\t-h,--help\tprints this help
"

declare -A REQUIRED_ARGS
REQUIRED_ARGS[-f]=1
REQUIRED_ARGS[-t]=1

VERBOSE=0

# JQ queries

ID_QUERY=".[].Id"
DIFF_FS_QUERY=".[].GraphDriver.Data.UpperDir"
MERGED_FS_QUERY=".[].GraphDriver.Data.MergedDir"
MOUNTS_QUERY=".[].Mounts[] | select(.RW == true)"  # only RW mounts

# OPTION VARIABLES

t_chroot=0

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

####################
## ARGUMENTS LOOP ##
####################
parse_args() {
    argvs=($@)
    inspect_file=""

    while (( "$#" )); do
        case "$1" in
            -f|--file)
                [[ ${REQUIRED_ARGS[-f]} -eq 1 ]] && REQUIRED_ARGS[-f]=0
                [[ $# -ge 2 ]] || fail "'-f': missing required parameter"
                [[ -e "$2" ]] || fail "'$2': file does not exist"
                shift

                inspect_file="$1"
                ;;
            -t|--type)
                [[ ${REQUIRED_ARGS[-t]} -eq 1 ]] && REQUIRED_ARGS[-t]=0
                [[ $# -ge 2 ]] || fail "'-t': missing required parameter"
                shift

                case "$1" in
                    files)
                        t_inspect_type="files"  # only informative
                        container_inspect_command="container_changed_files"
                        ;;
                    # other)
                    #     t_inspect_type="other"  # only informative
                    #     container_inspect_command="container_other_process"
                    #     ;;
                    *)
                        [[ $# -gt 0 ]] && fail "'-t': unknown parameter '$1'"
                        ;;
                esac
                debug "read -t options chroot=$t_chroot type=$t_inspect_type cmd=$container_inspect_command"
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
for arg in "${!REQUIRED_ARGS[@]}"; do
    [[ ${REQUIRED_ARGS[$arg]} -eq 1 ]] && fail "missing required argument '$arg'"
done

##########
## MAIN ##
##########

# list changed files from docker merged dir
container_changed_files() {
    debug "listing changed files: chroot=$t_chroot"
    merged_dir=$(jq -r "$MERGED_FS_QUERY" "$inspect_file")
    (( $t_chroot )) && find $merged_dir | sed "s|$merged_dir||g"
    (( ! $t_chroot )) && find $merged_dir
}


[ $container_inspect_command ] && eval "$container_inspect_command"

exit 0
