# sneakpeek

- spy on docker containers' files
- current supports overlay2 FS.
- utilizes the output of `docker inspect`

## sneakpeak.sh

- read JSON docker inspect output
- output all changed files in container

## get\_all\_containers.sh

- get all container names in the whole cluster
- returns lines of format: `NODE_IP,CONTAINER_NAME`


# Author

Tomas Bellus
