#!/bin/sh

# WARNING: This is not a strict POSIX script. The following exceptions apply
# - local variables for functions
# shellcheck disable=SC3043

# This file is a collection of functions used by all the other scripts

# Almost everywhere /bin/sh is actually a symlink. This instruction gives us the actual shell
SUIF_CURRENT_SHELL=$(readlink /proc/$$/exe)
export SUIF_CURRENT_SHELL

## Framework variables
# Convention: all variables from this framework are prefixed with SUIF_
# Variables defaults are specified in the init function
# client projects should source their variables with en .env file

# deprecated
newAuditSession() {
  export SUIF_AUDIT_BASE_DIR="${SUIF_AUDIT_BASE_DIR:-'/tmp'}"
  SUIF_SESSION_TIMESTAMP="$(date +%y-%m-%dT%H.%M.%S_%3N)"
  export SUIF_SESSION_TIMESTAMP
  export SUIF_AUDIT_SESSION_DIR="${SUIF_AUDIT_BASE_DIR}/${SUIF_SESSION_TIMESTAMP}"
  mkdir -p "${SUIF_AUDIT_SESSION_DIR}"
  return $?
}

initAuditSession() {
  export SUIF_AUDIT_BASE_DIR="${SUIF_AUDIT_BASE_DIR:-/tmp}"
  SUIF_SESSION_TIMESTAMP="${SUIF_SESSION_TIMESTAMP:-$(date +%Y-%m-%dT%H.%M.%S_%3N)}"
  export SUIF_SESSION_TIMESTAMP
  export SUIF_AUDIT_SESSION_DIR="${SUIF_AUDIT_BASE_DIR}/${SUIF_SESSION_TIMESTAMP}"
  mkdir -p "${SUIF_AUDIT_SESSION_DIR}"
  return $?
}

init() {
  #newAuditSession || return $?
  initAuditSession || return $?

  # For internal dependency checks,
  export SUIF_DEBUG_ON="${SUIF_DEBUG_ON:-0}"
  export SUIF_LOG_TOKEN="${SUIF_LOG_TOKEN:-SUIF}"
  # by default, we assume we are working connected to internet, put this on 0 for offline installations
  export SUIF_ONLINE_MODE="${SUIF_ONLINE_MODE:-1}"

  if [ "${SUIF_ONLINE_MODE}" -eq 0 ]; then
    # in offline mode the caller MUST provide the home folder for SUIF in the env var SUIF_HOME
    if [ ! -f "${SUIF_HOME}/01.scripts/commonFunctions.sh" ]; then
      return 104
    else
      export SUIF_CACHE_HOME="${SUIF_HOME}" # we already have everything
    fi
  else
    # by default use master branch
    export SUIF_HOME_URL="${SUIF_HOME_URL:-"https://raw.githubusercontent.com/SoftwareAG/sag-unattended-installations/main/"}"
    export SUIF_CACHE_HOME="${SUIF_CACHE_HOME:-"/tmp/suifCacheHome"}"
    mkdir -p "${SUIF_CACHE_HOME}"
  fi

  # SUPPRESS_STDOUT means we will not produce STD OUT LINES
  # Normally we want the see the output when we prepare scripts, and suppress it when we finished
  export SUIF_SUPPRESS_STDOUT="${SUIF_SUPPRESS_STDOUT:-0}"
}

init || exit $?

# all log functions recieve 1 parameter
# $1 - Message to log

logI() {
  if [ "${SUIF_SUPPRESS_STDOUT}" -eq 0 ]; then echo "$(date +%y-%m-%dT%H.%M.%S_%3N) ${SUIF_LOG_TOKEN} -INFO - ${1}"; fi
  echo "$(date +%y-%m-%dT%H.%M.%S_%3N) ${SUIF_LOG_TOKEN} -INFO - ${1}" >>"${SUIF_AUDIT_SESSION_DIR}/session.log"
}

logW() {
  if [ "${SUIF_SUPPRESS_STDOUT}" -eq 0 ]; then echo "$(date +%y-%m-%dT%H.%M.%S_%3N) ${SUIF_LOG_TOKEN} -WARN - ${1}"; fi
  echo "$(date +%y-%m-%dT%H.%M.%S_%3N) ${SUIF_LOG_TOKEN} -WARN - ${1}" >>"${SUIF_AUDIT_SESSION_DIR}/session.log"
}

logE() {
  if [ "${SUIF_SUPPRESS_STDOUT}" -eq 0 ]; then echo "$(date +%y-%m-%dT%H.%M.%S_%3N) ${SUIF_LOG_TOKEN} -ERROR- ${1}"; fi
  echo "$(date +%y-%m-%dT%H.%M.%S_%3N) ${SUIF_LOG_TOKEN} -ERROR- ${1}" >>"${SUIF_AUDIT_SESSION_DIR}/session.log"
}

logD() {
  if [ "${SUIF_DEBUG_ON}" -ne 0 ]; then
    if [ "${SUIF_SUPPRESS_STDOUT}" -eq 0 ]; then echo "$(date +%y-%m-%dT%H.%M.%S_%3N) ${SUIF_LOG_TOKEN} -DEBUG- ${1}"; fi
    echo "$(date +%y-%m-%dT%H.%M.%S_%3N) ${SUIF_LOG_TOKEN} -DEBUG- ${1}" >>"${SUIF_AUDIT_SESSION_DIR}/session.log"
  fi
}

logEnv() {
  if [ "${SUIF_DEBUG_ON}" -ne 0 ]; then
    if [ "${SUIF_SUPPRESS_STDOUT}" -eq 0 ]; then env | grep SUIF | sort; fi
    env | grep SUIF | sort >>"${SUIF_AUDIT_SESSION_DIR}/session.log"
  fi
}

logFullEnv() {
  if [ "${SUIF_DEBUG_ON}" -ne 0 ]; then
    if [ "${SUIF_SUPPRESS_STDOUT}" -eq 0 ]; then env | sort; fi
    env | grep SUIF | sort >>"${SUIF_AUDIT_SESSION_DIR}/session.log"
  fi
}

# Convention:
# f() function creates a RESULT_f variable for the outcome
# if not otherwise specified, 0 means success

controlledExec() {
  # Param $1 - command to execute in a controlled manner
  # Param $2 - tag for trace files
  local lCrtEpoch
  lCrtEpoch="$(date +%s)"
  eval "${1}" >"${SUIF_AUDIT_SESSION_DIR}/controlledExec_${lCrtEpoch}_${2}.out" 2>"${SUIF_AUDIT_SESSION_DIR}/controlledExec_${lCrtEpoch}_${2}.err"
  return $?
}

portIsReachable() {
  # Params: $1 -> host $2 -> port
  if [ -f /usr/bin/nc ]; then
    nc -z "${1}" "${2}" # alpine image
  else
    # shellcheck disable=SC2006,SC2086,SC3025,SC2034
    temp=$( (echo >/dev/tcp/${1}/${2}) >/dev/null 2>&1) # centos image
  fi
  # shellcheck disable=SC2181
  if [ $? -eq 0 ]; then echo 1; else echo 0; fi
}

portIsReachable2() {
  # Params: $1 -> host $2 -> port
  if [ -f /usr/bin/nc ]; then
    # shellcheck disable=SC2086
    nc -z ${1} ${2} # e.g. alpine image
  else
    # shellcheck disable=SC3025,SC2086
    (echo >/dev/tcp/${1}/${2}) >/dev/null 2>&1 # e.g. centos image
  fi
  return $?
}

# New urlencode approach, to render the script more portable
# Code taken from https://stackoverflow.com/questions/38015239/url-encoding-a-string-in-shell-script-in-a-portable-way
urlencodepipe() {
  local LANG=C; local c; while IFS= read -r c; do
    # shellcheck disable=SC2059
    case $c in [a-zA-Z0-9.~_-]) printf "$c"; continue ;; esac
    # shellcheck disable=SC2059
    printf "$c" | od -An -tx1 | tr ' ' % | tr -d '\n'
  done <<EOF
$(fold -w1)
EOF
  echo
}

# shellcheck disable=SC2059
urlencode() { printf "$*" | urlencodepipe ;}

# deprecated, not POSIX portable
urldecode() {
  # urldecode <string>
  # usage A=$(urldecode ${A_ENC})

  # shellcheck disable=SC3060
  local url_encoded="${1//+/ }"
  # shellcheck disable=SC3060
  printf '%b' "${url_encoded//%/\\x}"
}

# Parameters - huntForSuifFile
# $1 - relative Path to SUIF_HOME
# $2 - filename
huntForSuifFile() {
  if [ ! -f "${SUIF_CACHE_HOME}/${1}/${2}" ]; then
    if [ "${SUIF_ONLINE_MODE}" -eq 0 ]; then
      logE "File ${SUIF_CACHE_HOME}/${1}/${2} not found!"
      return 1 # File should exist, but it does not
    fi
    logI "File ${SUIF_CACHE_HOME}/${1}/${2} not found in local cache, attempting download"
    mkdir -p "${SUIF_CACHE_HOME}/${1}"
    curl "${SUIF_HOME_URL}/${1}/${2}" --silent -o "${SUIF_CACHE_HOME}/${1}/${2}"
    local RESULT_curl=$?
    if [ ${RESULT_curl} -ne 0 ]; then
      logE "curl failed, code ${RESULT_curl}"
      return 2
    fi
    logI "File ${SUIF_CACHE_HOME}/${1}/${2} downloaded successfully"
  fi
}

# Parameters - applyPostSetupTemplate
# $1 - Setup template directory, relative to <repo_home>/02.templates/02.post-setup
applyPostSetupTemplate() {
  logI "Applying post-setup template ${1}"
  huntForSuifFile "02.templates/02.post-setup/${1}" "apply.sh"
  local RESULT_huntForSuifFile=$?
  if [ ${RESULT_huntForSuifFile} -ne 0 ]; then
    logE "File ${SUIF_CACHE_HOME}/02.templates/02.post-setup/${1}/apply.sh not found!"
    return 1
  fi
  chmod u+x "${SUIF_CACHE_HOME}/02.templates/02.post-setup/${1}/apply.sh"
  local RESULT_chmod=$?
  if [ ${RESULT_chmod} -ne 0 ]; then
    logW "chmod command for apply.sh failed. This is not always a problem, continuing"
  fi
  logI "Calling apply.sh for template ${1}"
  #controlledExec "${SUIF_CACHE_HOME}/02.templates/02.post-setup/${1}/apply.sh" "PostSetupTemplateApply"
  "${SUIF_CACHE_HOME}/02.templates/02.post-setup/${1}/apply.sh"
  local RESULT_apply=$?
  if [ ${RESULT_apply} -ne 0 ]; then
    logE "Application of post-setup template ${1} failed, code ${RESULT_apply}"
    return 3
  fi
  logI "Post setup template ${1} applied successfully"
}

logEnv4Debug() {
  logD "Dumping environment variables for debugging purposes"

  if [ "${SUIF_DEBUG_ON}" -ne 0 ]; then
    if [ "${SUIF_SUPPRESS_STDOUT}" -eq 0 ]; then
      env | grep SUIF_ | grep -v PASS | grep -vi password | grep -vi dbpass | sort
    fi
    echo env | grep SUIF_ | grep -v PASS | grep -vi password | grep -vi dbpass | sort >>"${SUIF_AUDIT_SESSION_DIR}/session.log"
  fi
}

debugSuspend() {
  if [ "${SUIF_DEBUG_ON}" -ne 0 ]; then
    logD "Suspending for debug"
    tail -f /dev/null
  fi
}

# Rewritten for portability
# code inspired from https://stackoverflow.com/questions/3980668/how-to-get-a-password-from-a-shell-script-without-echoing
readSecretFromUser(){
  stty -echo
  secret="0"
  local s1 s2
  while [ "${secret}" = "0" ]; do
    printf "Please input %s: " "${1}"
    read -r s1
    printf "\n"
    printf "Please input %s again: " "${1}"
    read -r s2
    printf "\n"
    if [ "${s1}" = "${s2}" ]; then
      secret=${s1}
    else
      echo "Input do not match, retry"
    fi
    unset s1 s2
  done
  stty echo
}

# POSIX string substitution
# Parameters 
# $1 - original string
# $2 - charset what to substitute
# $3 - replacement charset
# ATTN: works char by char, not with substrings
strSubstPOSIX()
{
  # shellcheck disable=SC2086
  printf '%s' "$1" | tr $2 $3
}

commonFunctionsSourced(){
  return 0
}

logI "SLS common framework functions initialized. Current shell is ${SUIF_CURRENT_SHELL}"

if [ ! "${SUIF_CURRENT_SHELL}" = "/usr/bin/bash" ]; then
  logW "This framework has not been tested with this shell. Scripts are not guaranteed to work as expected"
fi
