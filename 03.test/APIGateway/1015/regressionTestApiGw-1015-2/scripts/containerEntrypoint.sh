#!/bin/sh

# shellcheck source-path=SCRIPTDIR/../../../../..
# shellcheck disable=SC2153,SC2046,SC3043

# This scripts sets up the local installation if it doesn't already exist
export SUIF_TEST_HARNESS_FOLDER="03.test/APIGateway/1015/ApiGw-1015-default-test-1"
export lLOG_PREFIX="$SUIF_TEST_HARNESS_FOLDER/containerEntrypoint.sh - "

if [ ! -d "${SUIF_HOME}" ]; then
  echo "[$lLOG_PREFIX] - FATAL - SUIF_HOME variable MUST point to an existing local folder! Current value is ${SUIF_HOME}"
    exit 1
fi

# Source framework functions
. "${SUIF_HOME}/01.scripts/commonFunctions.sh" || exit 4
. "${SUIF_HOME}/01.scripts/installation/setupFunctions.sh" || exit 5


# our configuration takes precedence in front of framework defaults, set it before sourcing the framework functions
if [ ! -d "${SUIF_LOCAL_SCRIPTS_HOME}" ]; then
    logE "[$lLOG_PREFIX] - Scripts folder not found: ${SUIF_LOCAL_SCRIPTS_HOME}"
    exit 2
fi

checkEnvVariables() {

  if [ -z "${SUIF_INSTALL_INSTALL_DIR+x}" ]; then
    logE "[$lLOG_PREFIX:checkEnvVariables()] - Variable SUIF_INSTALL_INSTALL_DIR was not set!"
    return 103
  fi

  if [ ! -d "${SUIF_INSTALL_INSTALL_DIR}" ]; then
    logE "[$lLOG_PREFIX:checkEnvVariables()] - Installation folder does not exist, but for this test it must be a mounted volume: ${SUIF_INSTALL_INSTALL_DIR}"
    return 104
  fi

  if [ ! -f "${SUIF_INSTALL_INSTALLER_BIN_MOUNT_POINT}" ]; then
    logE "[$lLOG_PREFIX:checkEnvVariables()] - ${SUIF_INSTALL_INSTALLER_BIN_MOUNT_POINT} is not a file, cannot continue"
    return 105
  fi

  if [ ! -f "${SUIF_INSTALL_INSTALLER_BIN_MOUNT_POINT}" ]; then
    logE "[$lLOG_PREFIX:checkEnvVariables()] - ${SUIF_INSTALL_INSTALLER_BIN_MOUNT_POINT} is not a file, cannot continue"
    return 106
  fi

  if [ ! -f "${SUIF_PATCH_SUM_BOOTSTRAP_BIN_MOUNT_POINT}" ]; then
    logE "[$lLOG_PREFIX:checkEnvVariables()] - ${SUIF_PATCH_SUM_BOOTSTRAP_BIN_MOUNT_POINT} is not a file, cannot continue"
    return 107
  fi
}

checkEnvVariables || exit $?

cp "${SUIF_INSTALL_INSTALLER_BIN_MOUNT_POINT}" "${SUIF_INSTALL_INSTALLER_BIN}"
cp "${SUIF_PATCH_SUM_BOOTSTRAP_BIN_MOUNT_POINT}" "${SUIF_PATCH_SUM_BOOTSTRAP_BIN}"

checkSetupTemplateBasicPrerequisites || exit $?

# If the installation is not present, do it now
if [ ! -d "${SUIF_INSTALL_INSTALL_DIR}/IntegrationServer" ]; then
  logI "[$lLOG_PREFIX] - Starting up for the first time, setting up ..."

    # Parameters - applySetupTemplate
    # $1 - Setup template directory, relative to <repo_home>/02.templates/01.setup
    applySetupTemplate "APIGateway/1007/default" || exit 6

fi

onInterrupt(){
	logI "[$lLOG_PREFIX:onInterrupt()] - Interrupted! Shutting down API Gateway"

	logI "[$lLOG_PREFIX:onInterrupt()] - Shutting down Integration server ..."
    cd "${SUIF_INSTALL_INSTALL_DIR}/profiles/IS_default/bin" || exit 111
    ./shutdown.sh
	logI "[$lLOG_PREFIX:onInterrupt()] - Shutting down Platform manager ..."
    cd "${SUIF_INSTALL_INSTALL_DIR}/profiles/SPM/bin" || exit 112
    ./shutdown.sh
	logI "[$lLOG_PREFIX:onInterrupt()] - Shutting down Elasticsearch ..."
    cd "${SUIF_INSTALL_INSTALL_DIR}/InternalDataStore/bin" || exit 113
    ./shutdown.sh

	exit 0 # managed expected exit
}

checkPrerequisites(){
    local c1=262144 # p1 -> vm.max_map_count
    local p1
    p1=$(sysctl "vm.max_map_count" | cut -d " " -f 3)
    # shellcheck disable=SC2086
    if [ ! $p1 -lt $c1 ]; then
        logI "[$lLOG_PREFIX:checkPrerequisites()] - vm.max_map_count is adequate ($p1)"
    else
        logE "[$lLOG_PREFIX:checkPrerequisites()] - vm.max_map_count is NOT adequate ($p1), container will exit now"
		return 1
    fi
} 

beforeStartConfig(){
  logI "[$lLOG_PREFIX:beforeStartConfig()] - Before Start Configuration"
}

afterStartConfig(){
    logI "Applying afterStartConfig"
    applyPostSetupTemplate ApiGateway/1005/ChangeAdministratorPassword
    envsubst < "${SUIF_APIGW_SETTINGS_JSON_FILE}" > /dev/shm/LBConfig.json
    export SUIF_APIGW_SETTINGS_JSON_FILE=/dev/shm/LBConfig.json
    applyPostSetupTemplate ApiGateway/1005/SetLoadBalancerConfiguration
    applyPostSetupTemplate ApiGateway/1005/PutSettings
}

trap "onInterrupt" INT TERM

logI "[$lLOG_PREFIX] - Starting up API Gateway server"
logI "[$lLOG_PREFIX] - Checking prerequisites ..."

checkPrerequisites || exit 7
crtPath=$(pwd)


beforeStartConfig

logI "[$lLOG_PREFIX] - Starting Elasticsearch ..."
cd "${SUIF_INSTALL_INSTALL_DIR}/InternalDataStore/bin" || exit 104
./startup.sh
logI "[$lLOG_PREFIX] - Starting Integration Server"
cd "${SUIF_INSTALL_INSTALL_DIR}/profiles/IS_default/bin" || exit 105
./console.sh & 

WPID=$!

while ! portIsReachable2 localhost 9072; do
    logI "Waiting for API Gateway to come up, sleeping 5..."
    sleep 5
done

afterStartConfig

wait ${WPID}

cd "$crtPath" || exit 106
