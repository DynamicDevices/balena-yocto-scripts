#!/bin/bash
set -e

source /manage-docker.sh

trap 'cleanup fail' SIGINT SIGTERM

# Start docker
echo "[INFO] Starting docker."
dockerd --data-root /scratch/docker > /var/log/docker.log &
wait_docker

_local_image=$(docker load -i /host/appimage.docker | cut -d: -f1 --complement | tr -d " " )
BALENAOS_ACCOUNT="balena_os"

echo "[INFO] Logging into $API_ENV as ${BALENAOS_ACCOUNT}"
export BALENARC_BALENA_URL=${API_ENV}
balena login --token "${TOKEN}"

_app_suffix=""
if [ "$ESR" = "true" ]; then
	_app_suffix="-esr"
fi

echo "Is this an ESR version? ${ESR}"
echo "[INFO] Pushing $_local_image to ${BALENAOS_ACCOUNT}/$APPNAME$_app_suffix"
_releaseID=$(balena deploy "${BALENAOS_ACCOUNT}/$APPNAME$_app_suffix" "$_local_image" | sed -n 's/.*Release: //p')
if [ "${_variant}" = "dev" ]; then
	release_version="${VERSION_HOSTOS}.dev"
	variant_str="development"
else
	release_version="${VERSION_HOSTOS}"
	variant_str="production"
fi

echo "[INFO] Tagging release ${_releaseID} with version ${release_version} and variant ${variant_str}"
balena tag set version $VERSION_HOSTOS --release $_releaseID
balena tag set variant $variant_str --release $_releaseID
if [ "$ESR" = "true" ]; then
	balena tag set meta-balena-base $META_BALENA_VERSION --release $_releaseID
fi
balena_api_set_release_version "${_releaseID}" "${BALENARC_BALENA_URL}" "${TOKEN}" "${release_version}"

cleanup
exit 0
