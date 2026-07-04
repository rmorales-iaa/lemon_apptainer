#!/usr/bin/env bash
set -euo pipefail

# Full LEMON pipeline runner using the sequential image and serial mosaic mode.
#
# Change only these variables to point at another dataset.
# Expected host layout:
#   $ROOT_DIR/in/$OBJECT/*.fits
#   $ROOT_DIR/out/$OBJECT/
# or:
#   $ROOT_DIR/input/$OBJECT/*.fits
#   $ROOT_DIR/output/$OBJECT/
#
# The script runs, in order:
#   1. mosaic
#   2. photometry
#   3. diffphot
#
# Optional positional arguments:
#   ./run_lemon_sequential.bash [OBJECT] [mosaic|photometry|diffphot]
#   ./run_lemon_sequential.bash [mosaic|photometry|diffphot]
#
# The default image is `lemon-juicer_sequential.sif`. Override with:
#   LEMON_IMAGE=/path/to/image.sif ./run_lemon_sequential.bash
#
# Useful environment variables:
#   OBJECT        Dataset name, default: HAT-P-16
#   ROOT_DIR      Data root; defaults to ./data if present, otherwise the
#                 legacy /home/rafa/apps/lemon/lemon_apptainer/data path
#   LEMON_MPROJEXEC_DEBUG
#                 Set to 1 to run mProjExec with Montage debug output
#   LEMON_MPROJEXEC_STATUS
#                 Optional path for the serial mProjExec status file inside
#                 the container. Leave unset to write Montage output to stderr.
#   LEMON_MOSAIC_WORKROOT
#                 Root directory for Montage temporary work trees inside the
#                 container. Defaults to /data/tmp/lemon-mosaic-work

OBJECT="${OBJECT:-HAT-P-16}"
APP_IMAGE=lemon-juicer_sequential.sif

usage() {
    cat <<'EOF'
Usage:
  ./run_lemon_sequential.bash [OBJECT] [mosaic|photometry|diffphot]
  ./run_lemon_sequential.bash [mosaic|photometry|diffphot]

This launcher always runs mosaic in serial mode.
EOF
}

STAGE=""
case "${1:-}" in
    "" )
        ;;
    -h|--help )
        usage
        exit 0
        ;;
    mosaic|photometry|diffphot )
        STAGE="$1"
        shift
        ;;
    * )
        OBJECT="$1"
        shift
        ;;
esac

if [[ -z "${STAGE}" ]]; then
    case "${1:-}" in
        "" )
            ;;
        mosaic|photometry|diffphot )
            STAGE="$1"
            shift
            ;;
        * )
            echo "Unknown stage: ${1}" >&2
            usage >&2
            exit 1
            ;;
    esac
fi

if [[ $# -gt 0 ]]; then
    echo "Unexpected argument: $1" >&2
    usage >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
default_root_dir="${script_dir}/data"
legacy_root_dir="/home/rafa/apps/lemon/lemon_apptainer/data"
LEMON_MPROJEXEC_DEBUG="${LEMON_MPROJEXEC_DEBUG:-0}"
HOST_TMP_ROOT="${script_dir}/tmp"
LEMON_MPROJEXEC_STATUS="${LEMON_MPROJEXEC_STATUS:-}"
LEMON_MOSAIC_WORKROOT="${LEMON_MOSAIC_WORKROOT:-/data/tmp/lemon-mosaic-work}"
if [[ -z "${ROOT_DIR:-}" ]]; then
    if [[ -d "${default_root_dir}/in/${OBJECT}" || -d "${default_root_dir}/input/${OBJECT}" ]]; then
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
MOSAIC_FILE="$OUTPUT_DIR/mosaic.fits"
PHOT_DB="$OUTPUT_DIR/phot.LEMONdB"
CURVES_DB="$OUTPUT_DIR/curves.LEMONdB"

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

if [[ ! -d "${INPUT_DIR}" ]]; then
    echo "Input directory not found: ${INPUT_DIR}" >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${HOST_TMP_ROOT}"
echo "Sanitizing tmp directory: ${HOST_TMP_ROOT}" >&2
rm -rf "${HOST_TMP_ROOT:?}"/* 2>/dev/null || true

echo "Running sequential LEMON pipeline for ${OBJECT}" >&2
echo "Input directory:  ${INPUT_DIR}" >&2
echo "Output directory: ${OUTPUT_DIR}" >&2
echo "Mosaic file:      ${MOSAIC_FILE}" >&2
echo "Photometry DB:    ${PHOT_DB}" >&2
echo "Curves DB:        ${CURVES_DB}" >&2
echo "Mosaic cores:     1 (forced sequential)" >&2
echo "Image:            ${image_path}" >&2
if [[ -n "${STAGE}" ]]; then
    echo "Stage:            ${STAGE}" >&2
else
    echo "Stage:            full pipeline" >&2
fi
if [[ -n "${LEMON_MPROJEXEC_STATUS}" ]]; then
    echo "mProjExec status: ${LEMON_MPROJEXEC_STATUS}" >&2
else
    echo "mProjExec status: disabled" >&2
fi
if [[ "${image_path}" == "${fallback_image_path}" ]]; then
    echo "Using fallback image. Rebuild the main image if runtime validation fails." >&2
fi

exec env -u LD_PRELOAD apptainer exec \
    --fakeroot \
    --writable-tmpfs \
    --pwd /tmp \
    --bind "${HOST_TMP_ROOT}:/data/tmp" \
    --bind "${INPUT_DIR}:/data/in" \
    --bind "${OUTPUT_DIR}:/data/out" \
    --env LEMON_STAGE="${STAGE}" \
    --env LEMON_MPROJEXEC_DEBUG="${LEMON_MPROJEXEC_DEBUG}" \
    --env LEMON_MPROJEXEC_STATUS="${LEMON_MPROJEXEC_STATUS}" \
    --env LEMON_MOSAIC_WORKROOT="${LEMON_MOSAIC_WORKROOT}" \
    --env LEMON_IRAF_RUNTIME=/data/tmp/lemon-iraf \
    --env PYRAF_NO_DISPLAY=1 \
    --env TMPDIR=/data/tmp \
    --env TEMP=/data/tmp \
    --env TMP=/data/tmp \
    "${image_path}" \
    bash -lc '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive
        export PATH=/opt/lemon:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        export HOME=/data/tmp/lemon-iraf-home
        export LEMON_IRAF_RUNTIME=/data/tmp/lemon-iraf
        export PYRAF_NO_DISPLAY=1
        export TMPDIR=/data/tmp
        export TEMP=/data/tmp
        export TMP=/data/tmp
        mkdir -p "$HOME"
        mkdir -p /data/tmp/lemon-bin
        real_mprojexec="$(command -v mProjExec)"
        if [[ -z "${real_mprojexec}" ]]; then
            echo "Missing required Montage executable in image: mProjExec" >&2
            exit 1
        fi
        cat > /data/tmp/lemon-bin/mProjExec <<'"'"'WRAP'"'"'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
have_status=0
have_debug=0
for arg in "${args[@]}"; do
    if [[ "${arg}" == "-s" ]]; then
        have_status=1
    elif [[ "${arg}" == "-d" ]]; then
        have_debug=1
    fi
done
        if [[ -n "${LEMON_MPROJEXEC_STATUS:-}" && "${have_status}" == "0" ]]; then
            args=("-s" "${LEMON_MPROJEXEC_STATUS}" "${args[@]}")
        fi
        if [[ -n "${LEMON_MPROJEXEC_STATUS:-}" ]]; then
            mkdir -p "$(dirname "${LEMON_MPROJEXEC_STATUS}")"
        fi
if [[ "${LEMON_MPROJEXEC_DEBUG}" == "1" && "${have_debug}" == "0" ]]; then
    args=("-d" "${args[@]}")
fi
exec "${MONTAGE_MPROJEXEC_REAL}" "${args[@]}"
WRAP
        chmod +x /data/tmp/lemon-bin/mProjExec
        export MONTAGE_MPROJEXEC_REAL="${real_mprojexec}"
        export PATH=/data/tmp/lemon-bin:$PATH
        echo "[bootstrap] Checking Python, IRAF, and Montage runtime"
        python -c "import montage_wrapper" >/dev/null
        python -c "import pyraf.iraf; pyraf.iraf.noao" >/dev/null
        for cmd in mImgtbl mMakeHdr mProjExec mAdd mConvert; do
            command -v "$cmd" >/dev/null || {
                echo "Missing required Montage executable in image: $cmd" >&2
                exit 1
            }
        done
        echo "[bootstrap] Sequential launcher forcing serial mosaic mode"
        echo "[bootstrap] mProjExec status file: ${LEMON_MPROJEXEC_STATUS}"
        echo "[bootstrap] Montage work root: ${LEMON_MOSAIC_WORKROOT}"
        if [[ "${LEMON_MPROJEXEC_DEBUG}" == "1" ]]; then
            echo "[bootstrap] mProjExec debug mode enabled"
        fi
        mkdir -p /data/out
        mkdir -p "${LEMON_MOSAIC_WORKROOT}"
        run_mosaic() {
            echo "[1/3] Starting mosaic"
            lemon mosaic /data/in/*.fits /data/out/mosaic.fits --cores 1 --overwrite
            test -f /data/out/mosaic.fits
            echo "[1/3] Mosaic complete: /data/out/mosaic.fits"
        }
        run_photometry() {
            test -f /data/out/mosaic.fits || {
                echo "Missing mosaic input: /data/out/mosaic.fits" >&2
                exit 1
            }
            echo "[2/3] Starting photometry"
            lemon photometry /data/out/mosaic.fits /data/in/*.fits /data/out/phot.LEMONdB --overwrite
            test -f /data/out/phot.LEMONdB
            echo "[2/3] Photometry complete: /data/out/phot.LEMONdB"
        }
        run_diffphot() {
            test -f /data/out/phot.LEMONdB || {
                echo "Missing photometry input: /data/out/phot.LEMONdB" >&2
                exit 1
            }
            echo "[3/3] Starting diffphot"
            lemon diffphot /data/out/phot.LEMONdB /data/out/curves.LEMONdB --overwrite
            test -f /data/out/curves.LEMONdB
            echo "[3/3] Diffphot complete: /data/out/curves.LEMONdB"
        }

        case "${LEMON_STAGE:-}" in
            "" )
                run_mosaic
                run_photometry
                run_diffphot
                ;;
            mosaic )
                run_mosaic
                ;;
            photometry )
                run_photometry
                ;;
            diffphot )
                run_diffphot
                ;;
            * )
                echo "Unsupported stage: ${LEMON_STAGE}" >&2
                exit 1
                ;;
        esac
    '
