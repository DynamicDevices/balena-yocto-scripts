#!/bin/bash
set -e

source /balena-docker.inc
source /balena-api.inc

trap 'balena_docker_stop fail' SIGINT SIGTERM

# Start docker
balena_docker_start "/scratch/docker" "/var/run" "/var/log/docker.log"
balena_docker_wait

_local_image=$(docker load -i /host/appimage.docker | cut -d: -f1 --complement | tr -d " " )
BALENAOS_ACCOUNT="${BALENAOS_ACCOUNT:-"balena_os"}"

echo "[INFO] Logging into $API_ENV as ${BALENAOS_ACCOUNT}"
export BALENARC_BALENA_URL=${API_ENV}
balena login --token "${TOKEN}"

if [ "$ESR" = "true" ]; then
	echo "Deploying ESR release"
	APPNAME="${APPNAME}-esr"
fi

echo "[INFO] Pushing $_local_image to ${BALENAOS_ACCOUNT}/$APPNAME"
_releaseID=$(balena deploy "${BALENAOS_ACCOUNT}/$APPNAME" "$_local_image" | sed -n 's/.*Release: //p')

# Legacy hostapp tagging
release_version="${VERSION_HOSTOS}"
if [ -n "${VARIANT}" ]; then
	if [ "${VARIANT}" = "dev" ]; then
		release_version="${release_version}.dev"
		variant_str="development"
	else
		variant_str="production"
	fi
	echo "[INFO] Tagging release ${_releaseID} with version ${release_version} and variant ${variant_str}"
	balena tag set version $VERSION_HOSTOS --release $_releaseID
	balena tag set variant $variant_str --release $_releaseID
	if [ "$ESR" = "true" ]; then
		balena tag set meta-balena-base $META_BALENA_VERSION --release $_releaseID
	fi
fi

balena_api_set_release_version "${_releaseID}" "${BALENARC_BALENA_URL}" "${TOKEN}" "${release_version}"

balena_docker_stop
exit 0
