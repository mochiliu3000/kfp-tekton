#!/bin/bash -e

# Copyright 2020 kubeflow.org
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# The scripts clones the kubeflow/pipelines repository and attempts to compile
# each Python DSL script found in the compiler testdata directory.
#
# Usage:
#   ./test_kfp_samples.sh [KFP version, default to 0.2.2]

KFP_VERSION=${1:-0.2.2}
KFP_REPO_URL="https://github.com/kubeflow/pipelines.git"

SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"
PROJECT_DIR="${TRAVIS_BUILD_DIR:-$(cd "${SCRIPT_DIR%/sdk/python/tests}"; pwd)}"
TEMP_DIR="${PROJECT_DIR}/temp"
VENV_DIR="${VIRTUAL_ENV:-${TEMP_DIR}/.venv}"
KFP_CLONE_DIR="${TEMP_DIR}/kubeflow/pipelines"
KFP_TESTDATA_DIR="${KFP_CLONE_DIR}/sdk/python/tests/compiler/testdata"
TEKTON_COMPILED_YAML_DIR="${TEMP_DIR}/tekton_compiler_output"
COMPILE_REPORT_FILE="${PROJECT_DIR}/sdk/python/tests/test_kfp_samples_report.txt"
COMPILER_OUTPUTS_FILE="${TEMP_DIR}/test_kfp_samples_output.txt"

mkdir -p "${TEMP_DIR}"
mkdir -p "${TEKTON_COMPILED_YAML_DIR}"

# clone kubeflow/pipeline repo to get the testdata DSL scripts
if [ ! -d "${KFP_CLONE_DIR}" ]; then
  git -c advice.detachedHead=false clone -b "${KFP_VERSION}" "${KFP_REPO_URL}" "${KFP_CLONE_DIR}" -q
else
  cd "${KFP_CLONE_DIR}"
  git -c advice.detachedHead=false checkout "${KFP_VERSION}" -f -q
  cd - &> /dev/null
fi
echo "KFP version: $(git --git-dir "${KFP_CLONE_DIR}"/.git tag --points-at HEAD)"

# check if we are running in a Python virtual environment, if not create one
if [ ! -d "${VENV_DIR}" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "${VENV_DIR}"
  source "${VENV_DIR}/bin/activate"
  pip install --upgrade pip
fi
source "${VENV_DIR}/bin/activate"

# install KFP-Tekton compiler, unless already installed
if ! (pip show "kfp-tekton" | grep Location | grep -q "${PROJECT_DIR}"); then
  pip install -e "${PROJECT_DIR}/sdk/python"
fi

echo  # just adding some separation for console output

# keep a record of the previous compilation status
SUCCESS_BEFORE=$(grep -c "SUCCESS" "${COMPILE_REPORT_FILE}")
FAILURE_BEFORE=$(grep -c "FAILURE" "${COMPILE_REPORT_FILE}")
TOTAL_BEFORE=$(grep -c . "${COMPILE_REPORT_FILE}")

# delete the previous compiler output file
rm -f "${COMPILER_OUTPUTS_FILE}"

for f in "${KFP_TESTDATA_DIR}"/*.py; do
  echo -e "\nCompiling ${f##*/}:" >> "${COMPILER_OUTPUTS_FILE}"
  if dsl-compile-tekton --py "${f}" --output "${TEKTON_COMPILED_YAML_DIR}/${f##*/}.yaml" >> "${COMPILER_OUTPUTS_FILE}" 2>&1;
  then
    echo "SUCCESS: ${f##*/}" | tee -a "${COMPILER_OUTPUTS_FILE}"
  else
    echo "FAILURE: ${f##*/}" | tee -a "${COMPILER_OUTPUTS_FILE}"
  fi
done | tee "${COMPILE_REPORT_FILE}"

# compile the report
SUCCESS=$(grep -c "SUCCESS" "${COMPILE_REPORT_FILE}")
FAILURE=$(grep -c "FAILURE" "${COMPILE_REPORT_FILE}")
TOTAL=$(grep -c . "${COMPILE_REPORT_FILE}")
(
  echo
  echo "Success: ${SUCCESS}"
  echo "Failure: ${FAILURE}"
  echo "Total:   ${TOTAL}"
) | tee -a "${COMPILE_REPORT_FILE}"
echo
echo "Compilation status report:   ${COMPILE_REPORT_FILE#${PROJECT_DIR}/}"
echo "Accumulated compiler logs:   ${COMPILER_OUTPUTS_FILE#${PROJECT_DIR}/}"
echo "Compiled Tekton YAML files:  ${TEKTON_COMPILED_YAML_DIR#${PROJECT_DIR}/}/"
echo

# for Travis/CI integration return exit code 1 if success rate declined
if [ ${SUCCESS} -lt "${SUCCESS_BEFORE}" ]; then
  echo "It appears that fewer KFP test scripts are compiling than before!"
  echo
  echo "Success before: ${SUCCESS_BEFORE}"
  echo "Failure before: ${FAILURE_BEFORE}"
  echo "Total before:   ${TOTAL_BEFORE}"
  exit 1
else
  exit 0
fi
