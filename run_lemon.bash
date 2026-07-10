#!/usr/bin/env bash
set -euo pipefail

# Full LEMON pipeline runner.
#
# Cleanup function to ensure proper termination of child processes
cleanup() {
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        return $exit_code
    fi
    pkill -P $$ 2>/dev/null || true
    pkill -f "mProjExecMPI.*LEMON_$$" 2>/dev/null || true
    exit $exit_code
}
trap cleanup EXIT INT TERM

# Usage / configuration
#   OBJECT        Dataset name, default: HAT-P-16
#   ROOT_DIR      Data root; defaults to ./data if present
#   MOSAIC_CORES  Number of cores, default: 4
#   LEMON_TIMEOUT Overall execution timeout in seconds, default: 2400
#   LEMON_IMAGE   Override image path
#   LEMON_MPROJEXEC_DEBUG  Set to 1 for Montage debug output
#   LEMON_MPROJEXEC_STATUS Optional status file path inside container
#   LEMON_MOSAIC_WORKROOT  Montage temp work dir, default /data/tmp/lemon-mosaic-work

OBJECT="${OBJECT:-HAT-P-16}"
APP_IMAGE=/mnt/uxmal_groups/common_data/apps/lemon_apptainer_images/lemon-juicer.sif

usage() {
    cat <<'EOF'
Usage:
  ./run_lemon.bash [OBJECT] [mosaic|photometry|diffphot]
  ./run_lemon.bash [mosaic|photometry|diffphot]

If no stage is provided, the full pipeline runs:
  mosaic -> photometry -> diffphot
EOF
}

STAGE=""
case "${1:-}" in
    "" ) ;;
    -h|--help ) usage; exit 0 ;;
    mosaic|photometry|diffphot ) STAGE="$1"; shift ;;
    * ) OBJECT="$1"; shift ;;
esac

if [[ -z "${STAGE}" ]]; then
    case "${1:-}" in
        "" ) ;;
        mosaic|photometry|diffphot ) STAGE="$1"; shift ;;
        * ) echo "Unknown stage: ${1}" >&2; usage >&2; exit 1 ;;
    esac
fi
if [[ $# -gt 0 ]]; then
    echo "Unexpected argument: $1" >&2; usage >&2; exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
default_root_dir="${script_dir}/data"
legacy_root_dir="/home/rafa/apps/lemon/lemon_apptainer/data"
MOSAIC_CORES="${MOSAIC_CORES:-4}"
LEMON_MPROJEXEC_DEBUG="${LEMON_MPROJEXEC_DEBUG:-0}"
HOST_TMP_ROOT="${script_dir}/tmp"
LEMON_MPROJEXEC_STATUS="${LEMON_MPROJEXEC_STATUS:-}"
LEMON_MOSAIC_WORKROOT="${LEMON_MOSAIC_WORKROOT:-/data/tmp/lemon-mosaic-work}"
LEMON_TIMEOUT="${LEMON_TIMEOUT:-2400}"
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
    INPUT_BASE="in"; OUTPUT_BASE="out"
else
    INPUT_BASE="input"; OUTPUT_BASE="output"
fi

INPUT_DIR="$ROOT_DIR/$INPUT_BASE/$OBJECT"
OUTPUT_DIR="$ROOT_DIR/$OUTPUT_BASE/$OBJECT"
MOSAIC_FILE="$OUTPUT_DIR/mosaic.fits"
PHOT_DB="$OUTPUT_DIR/phot.LEMONdB"
CURVES_DB="$OUTPUT_DIR/curves.LEMONdB"

default_image_path="$APP_IMAGE"
fallback_image_path="${script_dir}/lemon-juicer-test.sif"
image_path="${LEMON_IMAGE:-$default_image_path}"
if [[ -z "${LEMON_IMAGE:-}" && ! -f "${image_path}" && -f "${fallback_image_path}" ]]; then
    image_path="${fallback_image_path}"
fi
if [[ ! -f "${image_path}" ]]; then
    echo "LEMON image not found: ${image_path}" >&2; exit 1
fi
if [[ ! -d "${INPUT_DIR}" ]]; then
    echo "Input directory not found: ${INPUT_DIR}" >&2; exit 1
fi

# ---------------------------------------------------------------------------
# Sanitize output directory only for full pipeline or mosaic stage.
# photometry and diffphot need previous stage outputs to exist.
# ---------------------------------------------------------------------------
if [[ -z "${STAGE}" || "${STAGE}" == "mosaic" ]]; then
    echo "Sanitizing output directory: ${OUTPUT_DIR}" >&2
    rm -rf "$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"
mkdir -p "${HOST_TMP_ROOT}"

# Create mpirun wrapper to add --allow-run-as-root (required with --fakeroot)
mkdir -p "${HOST_TMP_ROOT}/lemon-bin"
cat > "${HOST_TMP_ROOT}/lemon-bin/mpirun" << 'MPIWRAP'
#!/usr/bin/env bash
exec /usr/bin/mpirun --allow-run-as-root "$@"
MPIWRAP
chmod +x "${HOST_TMP_ROOT}/lemon-bin/mpirun"

START_TIME=$(date +%s)

echo "Running LEMON pipeline for ${OBJECT}" >&2
echo "Input directory:  ${INPUT_DIR}" >&2
echo "Output directory: ${OUTPUT_DIR}" >&2
echo "Mosaic file:      ${MOSAIC_FILE}" >&2
echo "Photometry DB:    ${PHOT_DB}" >&2
echo "Curves DB:        ${CURVES_DB}" >&2
echo "Mosaic cores:     ${MOSAIC_CORES}" >&2
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
    echo "Using fallback image." >&2
fi
if [[ -n "${LEMON_TIMEOUT}" && "${LEMON_TIMEOUT}" != "0" ]]; then
    echo "Timeout:          ${LEMON_TIMEOUT}s" >&2
fi

timeout "${LEMON_TIMEOUT}" env -u LD_PRELOAD apptainer exec \
    --fakeroot \
    --writable-tmpfs \
    --pwd /tmp \
    --bind "${HOST_TMP_ROOT}:/data/tmp" \
    --bind "${INPUT_DIR}:/data/in" \
    --bind "${OUTPUT_DIR}:/data/out" \
    --env MOSAIC_CORES="${MOSAIC_CORES}" \
    --env LEMON_STAGE="${STAGE}" \
    --env LEMON_MPROJEXEC_DEBUG="${LEMON_MPROJEXEC_DEBUG}" \
    --env LEMON_MPROJEXEC_STATUS="${LEMON_MPROJEXEC_STATUS}" \
    --env LEMON_MOSAIC_WORKROOT="${LEMON_MOSAIC_WORKROOT}" \
    --env LEMON_IRAF_RUNTIME=/data/tmp/lemon-iraf \
    --env PYRAF_NO_DISPLAY=1 \
    --env TMPDIR=/data/tmp \
    --env TEMP=/data/tmp \
    --env TMP=/data/tmp \
    --env OMPI_MCA_btl=^openib \
    --env OMPI_MCA_btl_base_warn_component_unused=0 \
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
        export OMPI_ALLOW_RUN_AS_ROOT=1
        export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
        export OMPI_MCA_plm=isolated
        export OMPI_MCA_btl=^openib
        export OMPI_MCA_btl_base_warn_component_unused=0
        mkdir -p "$HOME"
        mkdir -p /data/tmp/lemon-bin

        # Wrap mProjExec to capture status/debug flags
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
    if [[ "${arg}" == "-s" ]]; then have_status=1
    elif [[ "${arg}" == "-d" ]]; then have_debug=1; fi
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

        # Ensure IRAF login.cl exists for pyraf/IRAF subprocesses.
        # pyraf checks ~/.iraf/login.cl (not ~/login.cl from mkiraf).
        # Must do this BEFORE importing pyraf — it prints the warning at init.
        if [[ ! -f "$HOME/.iraf/login.cl" ]]; then
            echo "[bootstrap] Creating IRAF login.cl"
            mkdir -p "$HOME/.iraf"
            cd "$HOME"
            mkiraf 2>/dev/null <<< "xgterm" || true
            # mkiraf creates login.cl in $HOME; link to where pyraf looks
            if [[ -f "$HOME/login.cl" && ! -f "$HOME/.iraf/login.cl" ]]; then
                ln -s "$HOME/login.cl" "$HOME/.iraf/login.cl"
            fi
            cd /
        fi

        python -c "import montage_wrapper" >/dev/null
        python -c "import pyraf" >/dev/null
        for cmd in mImgtbl mMakeHdr mProjExec mAdd mConvert; do
            command -v "$cmd" >/dev/null || {
                echo "Missing required Montage executable in image: $cmd" >&2
                exit 1
            }
        done

        mosaic_cores="${MOSAIC_CORES}"
        if command -v mpirun >/dev/null && command -v mProjExecMPI >/dev/null \
           && timeout 5 mpirun -n 1 /bin/true 2>/dev/null; then
            echo "[bootstrap] MPI Montage support detected (${mosaic_cores} cores)"
        else
            echo "[bootstrap] MPI Montage support not usable; forcing serial mode"
            mosaic_cores=1
        fi
        echo "[bootstrap] mProjExec status file: ${LEMON_MPROJEXEC_STATUS}"
        echo "[bootstrap] Montage work root: ${LEMON_MOSAIC_WORKROOT}"
        if [[ "${LEMON_MPROJEXEC_DEBUG}" == "1" ]]; then
            echo "[bootstrap] mProjExec debug mode enabled"
        fi

        mkdir -p /data/out
        mkdir -p "${LEMON_MOSAIC_WORKROOT}"
        # Pre-seed IRAF uparm from LEMON HOME for photometry
        if [[ -d /opt/lemon/uparm && ! -d "$HOME/uparm" ]]; then
            echo "[bootstrap] Seeding IRAF uparm from LEMON home"
            cp -a /opt/lemon/uparm "$HOME/uparm"
        fi

        run_mosaic() {
            echo "[1/3] Starting mosaic"
            if [[ "${mosaic_cores}" -gt 1 ]]; then
                echo "[mosaic] Running with ${mosaic_cores} MPI cores"
            fi
            lemon mosaic /data/in/*.fits /data/out/mosaic.fits --cores "${mosaic_cores}" --overwrite
            test -f /data/out/mosaic.fits
            echo "[1/3] Mosaic complete: /data/out/mosaic.fits"
        }
        run_photometry() {
            test -f /data/out/mosaic.fits || {
                echo "Missing mosaic input: /data/out/mosaic.fits" >&2; exit 1
            }
            echo "[2/3] Starting photometry"
            lemon photometry /data/out/mosaic.fits /data/in/*.fits /data/out/phot.LEMONdB --overwrite
            test -f /data/out/phot.LEMONdB
            echo "[2/3] Photometry complete: /data/out/phot.LEMONdB"
        }
        run_diffphot() {
            test -f /data/out/phot.LEMONdB || {
                echo "Missing photometry input: /data/out/phot.LEMONdB" >&2; exit 1
            }
            echo "[3/3] Starting diffphot"
            lemon diffphot /data/out/phot.LEMONdB /data/out/curves.LEMONdB --overwrite
            test -f /data/out/curves.LEMONdB
            echo "[3/3] Diffphot complete: /data/out/curves.LEMONdB"
        }

        case "${LEMON_STAGE:-}" in
            "" )        run_mosaic; run_photometry; run_diffphot ;;
            mosaic )    run_mosaic ;;
            photometry ) run_photometry ;;
            diffphot )  run_diffphot ;;
            * )         echo "Unsupported stage: ${LEMON_STAGE}" >&2; exit 1 ;;
        esac
    '
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
echo "=== LEMON pipeline finished ===" >&2
echo "Object:      ${OBJECT}" >&2
echo "Elapsed:     ${ELAPSED}s ($((ELAPSED / 60))m $((ELAPSED % 60))s)" >&2
