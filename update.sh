#! /bin/bash

function override_continue() {
  local _envrionmment=$1
  local _regions=$2
  local _application=$3
  local _override_path=$4
  local _array_regions=${_regions//,/$'\n'}
  continue=0
  for r in ${_array_regions}; do
    if [ -f "./${_envrionmment}/${r}/${_application}.override.yaml" ]; then
      diff <(yq -P 'sort_keys(..)' "${_override_path}") <(yq -P 'sort_keys(..)' "./${_envrionmment}/${r}/${_application}.override.yaml") > /dev/null
      exit_code="$?"
      if [ ! "${exit_code}" -eq 0 ]; then
        echo "[INFO] Drift detected"
        continue=1
        break
      fi
    else
      echo "[INFO] Missing override file in region ${r}"
      continue=1
      break
    fi
  done
}

function test_cue() {
  local _envrionmment=$1
  local _override_path=$2
  local _value_file=./${_envrionmment}/override.cue
  if ! cue vet "${_value_file}" "${_override_path}" --strict --simplify; then
    echo "[ERROR] Override file does not validate cue file"
    exit 1
  fi
}

function test_chart() {
  local _envrionmment=$1
  local _regions=$2
  local _application=$3
  local _override_path=$4
  local _kubeversions=$5
  local _repopath=./${_envrionmment}/chart
  local _array_regions=${_regions//,/$'\n'}
  local _array_kubeversions=${_kubeversions//,/$'\n'}
  for region in ${_array_regions}; do
    for kubeversion in ${_array_kubeversions}; do
      echo "[INFO] Kubeconform & helm for ${region} on ${kubeversion}"
      helm_args="-f ${_repopath}/values.yaml -f ${_repopath}/../${region}/values.yaml"
      if [  -f "${_repopath}/../${region}/${_application}.${_envrionmment}.${region}.values.yaml" ]; then
        helm_args+=" -f ${_repopath}/../${region}/${_application}.${_envrionmment}.${region}.values.yaml"
      fi
      if [  -f "${_repopath}/../${region}/${_application}.yaml" ]; then
        helm_args+=" -f ${_repopath}/../${region}/${_application}.yaml"
      fi
      result=$(helm template ${_repopath} ${helm_args} -f ${_override_path})
      if [ "$?" -ne 0 ]; then
        echo "[ERROR] Helm chart is not valid after override"
        exit 1
      fi
      echo "${result}" | kubeconform -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        -kubernetes-version "${kubeversion}" -strict
      if [ "$?" -ne 0 ]; then
        echo "[ERROR] kubeconform failed after override"
        exit 1
      fi
    done
  done
}

function update_value() {
  local _envrionmment=$1
  local _region=$2
  local _application=$3
  local _override_path=$4
  local _value_file=./${_envrionmment}/${_region}/${_application}.override.yaml
  yq "${_override_path}" > "${_value_file}"
  echo "[INFO] File ${_value_file} updated"
  if [ ! "${debug}" = true ]; then
    git add --all
    git commit -am "${_application} ${_envrionmment} ${_region} update override"
  fi
}

function setup_git() {
  if [ -z "${ACTOR_EMAIL}" ]; then
    ACTOR_EMAIL="${GITHUB_ACTOR}@finalcad.com"
  fi
  if [ -z "${ACTOR_NAME}" ]; then
    ACTOR_NAME="${GITHUB_ACTOR}"
  fi

  git config --global user.email "${ACTOR_EMAIL}"
  git config --global user.name "${ACTOR_NAME}"
}

function git_push() {
  set +eo pipefail # allow error
  # Error after 50 seconds / 5 attempts
  i=1
  while [ $i -lt 6 ]; do
    git pull --rebase && git push
    status=$?
    if [ ! "${status}" -eq 0 ]; then
      echo "[WARNING] Error while pushing changes, retrying in 10 seconds"
      sleep 10
    else
      echo "Changes pushed"
      break
    fi
    i=$((i + 1))
  done
  set -eo pipefail # disallow error
  if [ $i -gt 5 ]; then
    echo "[ERROR] Error while pushing changes, exiting..."
    exit 1
  fi
}

debug=${DEBUG:-false}

if [ "${debug}" = true ]; then
  echo "[DEBUG] Debug Mode: ON"
  echo "[INFO] Values environment: \"${ENVIRONMENT}\", region: \"${REGIONS}\", app: \"${APPNAME}\", path \"${OVERRIDE_PATH}\""
  set +x
else
  setup_git
fi

override_continue "${ENVIRONMENT}" "${REGIONS}" "${APPNAME}" "${OVERRIDE_PATH}"

if [ "${continue}" -eq 0 ]; then
  echo "[INFO] Nothing to change"
  exit 0
fi

test_cue "${ENVIRONMENT}" "${OVERRIDE_PATH}"
test_chart "${ENVIRONMENT}" "${REGIONS}" "${APPNAME}" "${OVERRIDE_PATH}" "${KUBEVERSIONS}"

# change comma to white space
regions=${REGIONS//,/$'\n'}
# For every defined regions, update values file with image sha
for region in ${regions}; do
  update_value "${ENVIRONMENT}" "${region}" "${APPNAME}" "${OVERRIDE_PATH}"
done

# Push changes
if [ ! "${debug}" = true ]; then
  git_push
fi
