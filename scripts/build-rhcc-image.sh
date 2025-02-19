#!/bin/bash -ex

# Basic help information
function show_help {
    echo "Usage: $0 <options>"
    echo "Options:"
    echo "  -p : Product to build (e.g. couchbase-server) (Required)"
    echo "  -v : Version of product to use (e.g. 5.1.0) (Required)"
    echo "  -b : Build number to use (eg. 1234) (Required)"
    echo "  -s : Build from staging repository (Optional, defaults to false)"
    echo "  -q : Quick build (disables docker build --no-cache)"
    echo "  -n : Dry run (don't push to docker registries)"
    exit 0
}

SCRIPT_DIR=$(dirname $(readlink -e -- "${BASH_SOURCE}"))

STAGING=""
CACHE_ARG="--no-cache"
DRYRUN=""

# Parse options and ensure required ones are there
while getopts :p:v:b:qsnh opt; do
    case ${opt} in
        p) PRODUCT="$OPTARG"
           ;;
        v) VERSION="$OPTARG"
           ;;
        b) BLD_NUM="$OPTARG"
           ;;
        s) STAGING="-staging"
           ;;
        q) CACHE_ARG=""
           ;;
        n) DRYRUN="yes"
           ;;
        h) show_help
           ;;
        \?) # Unrecognized option, show help
            echo -e \\n"Invalid option: ${OPTARG}" 1>&2
            show_help
    esac
done

if [[ -z "$PRODUCT" ]]; then
    echo "Product name (-p) is required"
    exit 1
fi

if [[ -z "$VERSION" ]]; then
    echo "Version of product (-v) is required"
    exit 1
fi

if [[ -z "$BLD_NUM" ]]; then
    echo "Build number of product (-b) is required"
    exit 1
fi
if [[ ${PRODUCT} == "couchbase-server" && $BLD_NUM -lt 10 ]]; then
    echo "Please use complete internal build number, not ${BLD_NUM}"
    exit 1
fi

# Use new UBI-based Dockerfile for Server 7.x or later, or SGW 3.x or later
if [[ ${PRODUCT} == "couchbase-server" && ${VERSION} =~ ^6.* ]]; then
    echo "Using old-school Dockerfile.old"
    DOCKERFILE=Dockerfile.old
elif [[ ${PRODUCT} == "sync-gateway" && ${VERSION} =~ ^2.* ]]; then
    echo "Using old-school Dockerfile.old"
    DOCKERFILE=Dockerfile.old
else
    DOCKERFILE=Dockerfile
fi

# Enter product directory
cd ${PRODUCT}

# Determine image name per project - these are always uploaded to GHCR,
# so the build server should have push access there
if [[ ${PRODUCT} == "couchbase-server" ]]; then
    INTERNAL_IMAGE_NAME=cb-rhcc/server
else
    INTERNAL_IMAGE_NAME=cb-rhcc/sync-gateway
fi

# Build and push images
for registry in ghcr.io build-docker.couchbase.com; do
    IMAGE=${registry}/${INTERNAL_IMAGE_NAME}:${VERSION}-${BLD_NUM}

    ${SCRIPT_DIR}/update-base.sh ${DOCKERFILE}
    echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    echo Building ${IMAGE}
    echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    docker build ${CACHE_ARG} \
      --build-arg PROD_VERSION=${VERSION} \
      --build-arg STAGING=${STAGING} \
      -f ${DOCKERFILE} -t ${IMAGE} .

    if [ "x${DRYRUN}" != "xyes" ]; then
        echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        echo Pushing ${IMAGE}
        echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        docker push ${IMAGE}
        docker rmi ${IMAGE}
    fi
done
