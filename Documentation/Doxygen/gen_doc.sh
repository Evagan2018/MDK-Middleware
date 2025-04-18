#!/usr/bin/env bash
# Version: 3.0
# Date: 2023-11-06
# This bash script generates MDK-Middleware documentation
#
# Pre-requisites:
# - bash shell (for Windows: install git for Windows)
# - curl
# - doxygen 1.13.2
# - mscgen 0.20
# - linkchecker (can be skipped with -s)

set -o pipefail

# Set version of gen pack library
# For available versions see https://github.com/Open-CMSIS-Pack/gen-pack/tags.
# Use the tag name without the prefix "v", e.g., 0.7.0
REQUIRED_GEN_PACK_LIB="0.11.3"

DIRNAME=$(dirname "$(readlink -f "$0")")
GENDIR=../html
REQ_DXY_VERSION="1.13.2"
REQ_MSCGEN_VERSION="0.20"

RUN_LINKCHECKER=1
COMPONENTS=()

function usage() {
  echo "Usage: $(basename "$0") [-h] [-s] [-c <comp>]"
  echo " -h,--help               Show usage"
  echo " -s,--no-linkcheck       Skip linkcheck"
  echo " -c,--component <comp>   Select component <comp> to generate documentation for. "
  echo "                         Can be given multiple times. Defaults to all components."
}

while [[ $# -gt 0 ]]; do
  case $1 in
    '-h'|'help')
      usage
      exit 1
    ;;
    '-s'|'--no-linkcheck')
      RUN_LINKCHECKER=0
    ;;
    '-c'|'--component')
      shift
      COMPONENTS+=("$1")
    ;;
    *)
      echo "Invalid command line argument: $1" >&2
      usage
      exit 1
    ;;
  esac
  shift # past argument
done

############ DO NOT EDIT BELOW ###########

# Set GEN_PACK_LIB_PATH to use a specific gen-pack library root
# ... instead of bootstrap based on REQUIRED_GEN_PACK_LIB
if [[ -f "${GEN_PACK_LIB_PATH}/gen-pack" ]]; then
  . "${GEN_PACK_LIB_PATH}/gen-pack"
else
  . <(curl -sL "https://raw.githubusercontent.com/Open-CMSIS-Pack/gen-pack/main/bootstrap")
fi

find_git
find_doxygen "${REQ_DXY_VERSION}"
find_utility "mscgen" "-l | grep 'Mscgen version' | sed -r -e 's/Mscgen version ([^,]+),.*/\1/'" "${REQ_MSCGEN_VERSION}"
[[ ${RUN_LINKCHECKER} != 0 ]] && find_linkchecker

if [ -z "${VERSION_FULL}" ]; then
  VERSION_FULL=$(git_describe "v")
fi

pushd "${DIRNAME}" > /dev/null || exit 1

echo_log "Generating documentation ..."

function generate() {
  if [[ ! (${#COMPONENTS[@]} == 0 || ${COMPONENTS[*]} =~ $1) ]]; then
    return
  fi

  pushd "$1" > /dev/null || exit 1

  projectName=$(grep -E "PROJECT_NAME\s+=" "$1.dxy.in" | sed -r -e 's/[^"]*"([^"]+)".*/\1/')
  projectNumberFull="$2"
  if [ -z "${projectNumberFull}" ]; then
    projectNumberFull=$(grep -E "PROJECT_NUMBER\s+=" "$1.dxy.in" | sed -r -e 's/[^"]*"[^0-9]*(([0-9]+\.[0-9]+(\.[0-9]+)?(-.+)?)?)".*/\1/')
  fi
  if [ -z "${projectNumberFull}" ]; then
    projectNumberFull=$(grep -E "<bundle Cbundle=\"MDK\"" "../../../Keil.MDK-Middleware.pdsc" | grep -E "${1:0:3}" | sed -r -e 's/[^"]*"[^0-9]*(([0-9]+\.[0-9]+(\.[0-9]+)?(-.+)?)?)".*/\1/')
  fi
  projectNumber="${projectNumberFull%+*}"
  datetime=$(date -u +'%a %b %e %Y %H:%M:%S')
  year=$(date -u +'%Y')

  sed -e "s/{projectNumber}/${projectNumber}/" "$1.dxy.in" > "$1.dxy"

  if [ $1 == "USB" ]; then
    # Replacing '%Instance%' with 'n' in all USB templates and storing them in Doxygen/USB/src/ folder
    TOOL_PATH="../../../Components/USB/Template"
    INSTANCE="n"
    found_files=$(find "$TOOL_PATH" -type f -name "USBD*")
    mkdir -p "./src/template/"
    for filename in $found_files; do
      if [[ -f "$filename" ]]; then
        new_filename=$(basename "$filename")
        sed "s/%Instance%/$INSTANCE/g" "$filename" > "./src/template/${new_filename}"
      fi
    done
  fi

  mkdir -p "${DIRNAME}/${GENDIR}/$1/"

  # if [ $1 == "General" ]; then
  #   git_changelog -f html -p "v" > src/revision_history.txt
  # fi

  echo_log "\"${UTILITY_DOXYGEN}\" \"$1.dxy\""
  "${UTILITY_DOXYGEN}" "$1.dxy"

  mkdir -p "${DIRNAME}/${GENDIR}/$1/search/"
  cp -f "${DIRNAME}/style_template/search.css" "${DIRNAME}/${GENDIR}/$1/search/"
  cp -f "${DIRNAME}/style_template/navtree.js" "${DIRNAME}/${GENDIR}/$1/"
  cp -f "${DIRNAME}/style_template/resize.js" "${DIRNAME}/${GENDIR}/$1/"

  sed -e "s/{datetime}/${datetime}/" "${DIRNAME}/style_template/footer.js.in" \
    | sed -e "s/{year}/${year}/" \
    | sed -e "s/{projectName}/${projectName}/" \
    | sed -e "s/{projectNumber}/${projectNumber}/" \
    | sed -e "s/{projectNumberFull}/${projectNumberFull}/" \
    > "${DIRNAME}/${GENDIR}/$1/footer.js"

  popd > /dev/null || exit 1
}

generate "General" "${VERSION_FULL}"
generate "FileSystem"
generate "Network"
generate "USB"

cp -f "${DIRNAME}/index.html" "${DIRNAME}/../html/"

popd > /dev/null || exit 1

[[ ${RUN_LINKCHECKER} != 0 ]] && check_links --timeout 120 "${DIRNAME}/../html/index.html" "${DIRNAME}"

exit 0
