#!/usr/bin/env bash
set -euo pipefail

# Juicer launcher for a LEMON curves database.
#
# Change only these variables to point at another dataset.
# Expected host layout:
#   $ROOT_DIR/out/$OBJECT/curves.LEMONdB
# or:
#   $ROOT_DIR/output/$OBJECT/curves.LEMONdB
#
# The default image is `lemon-juicer.sif`. If it does not exist yet, the
# script falls back to `lemon-juicer-test.sif`. Override with:
#   LEMON_IMAGE=/path/to/image.sif ./run_juicer.bash
#
# Optional positional argument:
#   ./run_juicer.bash [OBJECT]
#
# Useful environment variables:
#   OBJECT    Dataset name, default: HAT-P-16
#   ROOT_DIR  Data root; defaults to ./data if present, otherwise the legacy
#             /home/rafa/apps/lemon/lemon_apptainer/data path


OBJECT="${OBJECT:-HAT-P-16}"
APP_IMAGE=lemon-juicer.sif

usage() {
    cat <<'EOF'
Usage:
  ./run_juicer.bash [OBJECT]
EOF
}

case "${1:-}" in
    "" )
        ;;
    -h|--help )
        usage
        exit 0
        ;;
    * )
        OBJECT="$1"
        shift
        ;;
esac

if [[ $# -gt 0 ]]; then
    echo "Unexpected argument: $1" >&2
    usage >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
default_root_dir="${script_dir}/data"
legacy_root_dir="/home/rafa/apps/lemon/lemon_apptainer/data"
HOST_TMP_ROOT="${script_dir}/tmp"
if [[ -z "${ROOT_DIR:-}" ]]; then
    if [[ -d "${default_root_dir}/out/${OBJECT}" || -d "${default_root_dir}/output/${OBJECT}" ]]; then
        ROOT_DIR="${default_root_dir}"
    else
        ROOT_DIR="${legacy_root_dir}"
    fi
else
    ROOT_DIR="${ROOT_DIR}"
fi

if [[ -d "${ROOT_DIR}/in/${OBJECT}" || -d "${ROOT_DIR}/out" ]]; then
    INPUT_BASE="in"
    OUTPUT_BASE="out"
else
    INPUT_BASE="input"
    OUTPUT_BASE="output"
fi

INPUT_DIR="$ROOT_DIR/$INPUT_BASE/$OBJECT"
OUTPUT_DIR="$ROOT_DIR/$OUTPUT_BASE/$OBJECT"
mkdir -p "${HOST_TMP_ROOT}"
mkdir -p "${HOST_TMP_ROOT}/lemon-iraf-home/.local/share"

default_image_path="${script_dir}/$APP_IMAGE"
fallback_image_path="${script_dir}/lemon-juicer-test.sif"
image_path="${LEMON_IMAGE:-$default_image_path}"

if [[ -z "${LEMON_IMAGE:-}" && ! -f "${image_path}" && -f "${fallback_image_path}" ]]; then
    image_path="${fallback_image_path}"
fi

if [[ ! -f "${image_path}" ]]; then
    echo "LEMON image not found: ${image_path}" >&2
    exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set. Juicer needs X11 forwarding." >&2
    exit 1
fi

if [[ ! -f "${OUTPUT_DIR}/curves.LEMONdB" ]]; then
    echo "Curves database not found: ${OUTPUT_DIR}/curves.LEMONdB" >&2
    exit 1
fi

echo "Launching Juicer for ${OBJECT}" >&2
echo "Database: ${OUTPUT_DIR}/curves.LEMONdB" >&2
echo "Image:    ${image_path}" >&2

exec env -u LD_PRELOAD apptainer exec \
    --fakeroot \
    --pwd /tmp \
    --bind "${HOST_TMP_ROOT}:/data/tmp" \
    --bind /tmp/.X11-unix:/tmp/.X11-unix \
    --bind "${OUTPUT_DIR}:/data/out" \
    --env DISPLAY="${DISPLAY}" \
    --env TMPDIR=/data/tmp \
    --env TEMP=/data/tmp \
    --env TMP=/data/tmp \
    --env HOME=/data/tmp/lemon-iraf-home \
    "${image_path}" \
    /usr/local/bin/juicer /data/out/curves.LEMONdB
