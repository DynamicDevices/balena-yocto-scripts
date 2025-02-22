#!/bin/bash

[ "${VERBOSE}" = "verbose" ] && set -x
set -e

NAMESPACE=${NAMESPACE:-balena}

print_help() {
	echo -e "Script options:\n\
	\t\t -h | --help\n
	\t\t -m | --machine\n\
	\t\t\t (mandatory) Machine to build for. This is a mandatory argument\n
	\t\t --shared-dir\n\
	\t\t\t (mandatory) Directory where to store shared downloads and shared sstate.\n
	\t\t -d | --os-dev\n\
	\t\t\t Build an OS development image\n
	\t\t -a | --additional-variable\n\
	\t\t\t (optional) Inject additional local.conf variables. The format of the arguments needs to be VARIABLE=VALUE.\n\
	\t\t --meta-balena-branch\n\
	\t\t\t (optional) The meta-balena branch to checkout before building.\n\
\t\t\t\t Default value is __ignore__ which means it builds the meta-balena revision as configured in the git submodule.\n
	\t\t --supervisor-version\n\
	\t\t\t (optional) The balena supervisor release version to be included in the build.\n\
\t\t\t\t Default value is __ignore__ which means use the supervisor version already included in the meta-balena submodule.\n
	\t\t --preserve-build\n\
	\t\t\t (optional) Do not delete existing build directory.\n\
\t\t\t\t Default is to delete the existing build directory.\n
	\t\t --preserve-container\n\
	\t\t\t (optional) Do not delete the yocto build docker container when it exits.\n\
\t\t\t\t Default is to delete the container where the yocto build is taking place when this container exits.\n
	\t\t --ami-image-type\n\
	\t\t\t (optional) Specify image type to use for AMI image creation.\n\
\t\t\t\t Defaults to using direct boot image, set to *installer* to use the installer image instead .\n\
	\t\t --bb-args\n\
	\t\t\t (optional) Pass extra bitbake arguments\n\
\t\t\t\t Defaults to false.\n\
	\t\t --esr\n\
	\t\t\t (optional) Is this an ESR build\n\
\t\t\t\t Defaults to false.\n"
}

automation_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source "${automation_dir}/include/balena-lib.inc"
source "${automation_dir}/include/balena-deploy.inc"

rootdir="$( cd "$( dirname "$0" )" && pwd )/../../"
WORKSPACE=${WORKSPACE:-$rootdir}
ENABLE_TESTS=${ENABLE_TESTS:=false}
ESR=${ESR:-false}
AMI=${AMI:-false}
BARYS_ARGUMENTS_VAR="--remove-build"
REMOVE_CONTAINER="--rm"
OS_DEVELOPMENT=${OS_DEVELOPMENT:-false}

# process script arguments
args_number="$#"
while [[ $# -ge 1 ]]; do
	arg=$1
	case $arg in
		-h|--help)
			print_help
			exit 0
			;;
		-m|--machine)
			if [ -z "$2" ]; then
				echo "-m|--machine argument needs a machine name"
				exit 1
			fi
			MACHINE="$2"
			;;
		--shared-dir)
			if [ -z "$2" ]; then
				echo "--shared-dir needs directory name where to store shared downloads and sstate data"
				exit 1
			fi
			JENKINS_PERSISTENT_WORKDIR="$2"
			shift
			;;
		-a|--additional-variable)
			if [ -z "$2" ]; then
				echo "\"$1\" needs an argument in the format VARIABLE=VALUE"
				exit 1
			fi
			if echo "$2" | grep -vq '^[A-Za-z0-9_-]*='; then
				echo "\"$2\" has the wrong argument format for \"$1\". Read help."
				exit 1
			fi
			BARYS_ARGUMENTS_VAR="$BARYS_ARGUMENTS_VAR $1 $2"
			shift
			;;
		--meta-balena-branch)
			if [ -z "$2" ]; then
				echo "--meta-balena-branch argument needs a meta-balena branch name (if this option is not used, the default value is __ignore__)"
				exit 1
			fi
			metaBalenaBranch="${metaBalenaBranch:-$2}"
			;;
		--supervisor-version)
			if [ -z "$2" ]; then
				echo "--supervisor-version argument needs a balena supervisor release version (if this option is not used, the default value is __ignore__)"
				exit 1
			fi
			supervisorVersion="${supervisorVersion:-$2}"
			;;
		--ami-image-type)
			if [ -z "$2" ]; then
				echo "--ami-image-type argument needs an image type to use , by default it uses the direct boot image)"
				exit 1
			fi
			AMI_IMAGE_TYPE="${AMI_IMAGE_TYPE:-${2}}"
			;;
		--esr)
			ESR="true"
			;;
		-d|--os-dev)
			OS_DEVELOPMENT="true"
			;;
		--preserve-build)
			PRESERVE_BUILD=1
			BARYS_ARGUMENTS_VAR=${BARYS_ARGUMENTS_VAR//--remove-build/}
			;;
		--preserve-container)
			REMOVE_CONTAINER=""
			;;
		--ami)
			AMI="true"
			;;
		--bb-args)
			if [ -z "$2" ]; then
				echo "--bb-args argument needs to be specified"
				exit 1
			fi
			BARYS_ARGUMENTS_VAR="$BARYS_ARGUMENTS_VAR --bitbake-args ${2}"
			;;
	esac
	shift
done

metaBalenaBranch=${metaBalenaBranch:-__ignore__}
supervisorVersion=${supervisorVersion:-__ignore__}

# Sanity checks
if [ -z "$MACHINE" ] || [ -z "$JENKINS_PERSISTENT_WORKDIR" ]; then
	echo -e "\n[ERROR] You are missing one of these arguments:\n
\t -m <MACHINE>\n
\t --shared-dir <PERSISTENT_WORKDIR>\n
\t --build-flavor <BUILD_FLAVOR_TYPE>\n\n
Run with -h or --help for a complete list of arguments.\n"
	exit 1
fi

# When supervisorVersion is provided, set the appropiate barys argument
if [ "$supervisorVersion" != "__ignore__" ]; then
	BARYS_ARGUMENTS_VAR="$BARYS_ARGUMENTS_VAR --supervisor-version $supervisorVersion"
fi

# Checkout meta-balena
if [ "$metaBalenaBranch" = "__ignore__" ]; then
	echo "[INFO] Using the default meta-balena revision (as configured in submodules)."
else
	echo "[INFO] Using special meta-balena revision from build params."
	pushd "$WORKSPACE/layers/meta-balena" > /dev/null 2>&1
	git config --add remote.origin.fetch '+refs/pull/*:refs/remotes/origin/pr/*'
	git fetch --all
	git checkout --force "$metaBalenaBranch"
	git submodule update --init --recursive
	popd > /dev/null 2>&1
fi

if [ "${OS_DEVELOPMENT}" = "true" ]; then
	BARYS_ARGUMENTS_VAR="${BARYS_ARGUMENTS_VAR} -d"
fi

"${automation_dir}"/../build/balena-build.sh -d "${MACHINE}" -s "${JENKINS_PERSISTENT_WORKDIR}" -a "$(balena_lib_environment)" -g "${BARYS_ARGUMENTS_VAR}"
# Do not check for artifacts as when discontinuing device types build artifacts are not created, but device-type.json needs to be deployed to mark the device as discontinued

if [ "$ENABLE_TESTS" = true ]; then
	# Run the test script in the device specific repository
	if [ -f "$WORKSPACE/tests/start.sh" ]; then
		echo "Custom test file exists - Beginning test"
		/bin/bash "$WORKSPACE/tests/start.sh"
	else
		echo "No custom test file exists - Continuing ahead"
	fi
fi

# Jenkins artifacts
echo "[INFO] Starting creating jenkins artifacts..."
balena_deploy_artifacts "${MACHINE}" "$WORKSPACE/deploy-jenkins" "true"

# Deploy
if [ "$deploy" = "yes" ]; then
	echo "[INFO] Starting deployment..."

	secureBoot="no"
	if [ -n "${SIGN_API_URL}" ]; then
		secureBoot="yes"
	fi

	balena_deploy_to_s3 "$MACHINE" "${ESR}" "${deployTo}"
	_image_path=$(find "${WORKSPACE}/build/tmp/deploy/" -name "balena-image-${MACHINE}.docker" -type l || true)
	if [ -n "${_image_path}" ] && [ -f "${_image_path}" ]; then
		balena_deploy_block "$(balena_lib_get_slug "${MACHINE}")" "${MACHINE}" "${_bootable:-1}" "${_image_path}" "${deploy}" "${final}" "${secureBoot}"
	else
		echo "[ERROR]:balena_deploy_hostapp: No hostapp to release"
		exit 1
	fi

	if [ "$AMI" = "true" ] && [ "${final}" = "yes" ]; then
		echo "[INFO] Generating AMI"
		export automation_dir
		export MACHINE
		export AMI_IMAGE_TYPE
		"${automation_dir}"/jenkins_generate_ami.sh
	fi

fi

# Cleanup
# Keep this after writing all artifacts
if [ "${PRESERVE_BUILD}" != "1" ]; then
	rm -rf $WORKSPACE/build
fi
