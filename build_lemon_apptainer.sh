#!/usr/bin/env bash
set -euo pipefail

# Build a LEMON + Juicer Apptainer image.
#
# Defaults:
#   output image: lemon-juicer.sif
#   LEMON ref:    master
#
# Useful environment variables:
#   LEMON_REF            Git branch/tag/commit to build
#   APPTAINER_BUILD_ARGS Extra arguments passed to `apptainer build`
#   WORK_ROOT            Base directory for local temporary build files
#   BUILD_TMP_ROOT       Directory used as APPTAINER_TMPDIR
#   BUILD_CACHE_ROOT     Directory used as APPTAINER_CACHEDIR
#   MKSQUASHFS_ARGS      Extra mksquashfs arguments, default: -processors 1
#   MONTAGE_REF          Git branch/tag/commit for Montage source build
#
# Build temp/cache default to local storage under /var/tmp/.../lemon_apptainer
# instead of the repository path. This avoids dpkg stalls seen when Apptainer
# build state is placed on NFS.
#
# Example:
#   ./build_lemon_apptainer.sh
#   LEMON_REF=v0.4.4 ./build_lemon_apptainer.sh lemon-juicer.sif

IMAGE_NAME="${1:-lemon-juicer.sif}"
LEMON_REF="${LEMON_REF:-master}"
BUILD_ARGS="${APPTAINER_BUILD_ARGS:-}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
default_local_root="${TMPDIR:-/var/tmp}/${USER:-$(id -un 2>/dev/null || echo unknown)}/lemon_apptainer"
WORK_ROOT="${WORK_ROOT:-$default_local_root}"
BUILD_TMP_ROOT="${BUILD_TMP_ROOT:-$WORK_ROOT/tmp/build}"
BUILD_CACHE_ROOT="${BUILD_CACHE_ROOT:-$WORK_ROOT/tmp/cache}"
MKSQUASHFS_ARGS="${MKSQUASHFS_ARGS:--processors 1}"
MONTAGE_REF="${MONTAGE_REF:-main}"
IMAGE_NAME="$(readlink -f "${IMAGE_NAME}")"
BUILD_AUTHOR="${USER:-$(id -un 2>/dev/null || echo unknown)}"

if ! command -v apptainer >/dev/null 2>&1; then
    echo "apptainer is required but was not found in PATH" >&2
    exit 1
fi

build_mode=()
if [[ "${EUID}" -ne 0 ]]; then
    build_mode+=(--fakeroot)
fi

mkdir -p "${BUILD_TMP_ROOT}" "${BUILD_CACHE_ROOT}"
tmpdir="$(mktemp -d "${BUILD_TMP_ROOT}/def.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

def_file="${tmpdir}/lemon-juicer.def"

cat > "${def_file}" <<EOF
Bootstrap: docker
From: ubuntu:18.04

%labels
    Author ${BUILD_AUTHOR}
    Application LEMON
    Version ${LEMON_REF}
    Description LEMON differential photometry pipeline with Juicer UI

%help
    This image installs LEMON from https://github.com/vterron/lemon together
    with the Juicer GUI and the external astronomy tools that LEMON expects.

    Main entry points:
      apptainer run IMAGE.sif --help
      apptainer exec IMAGE.sif lemon --help
      apptainer exec IMAGE.sif juicer /path/to/file.LEMONdB

    For the GUI, forward X11 from the host, for example:
      apptainer exec --bind /tmp/.X11-unix:/tmp/.X11-unix \\
        --env DISPLAY=\$DISPLAY IMAGE.sif juicer file.LEMONdB

    This recipe forces a source build of matplotlib 1.5.3 so Juicer gets
    the legacy GTK2 extensions required by backend_gtkagg.

%environment
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8
    export PYTHONUNBUFFERED=1
    export PYRAF_NO_DISPLAY=1
    export MPLBACKEND=GTKAgg
    export LEMON_IRAF_RUNTIME=/tmp/lemon-iraf
    export LEMON_MPROJEXEC_DEBUG=0
    export LEMON_MPROJEXEC_STATUS=/tmp/mProjExec.status
    export OMPI_ALLOW_RUN_AS_ROOT=1
    export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
    export OMPI_MCA_plm=isolated
    export PATH=/opt/lemon:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

%post
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y --no-install-recommends \
        apt-utils \
        build-essential \
        ca-certificates \
        csh \
        dbus-x11 \
        git \
        iraf \
        iraf-noao \
        libfreetype6-dev \
        libgtk2.0-dev \
        libopenmpi-dev \
        libpng-dev \
        montage \
        openmpi-bin \
        python \
        python-aplpy \
        python-astropy \
        python-cairo-dev \
        python-configparser \
        python-gi \
        python-glade2 \
        python-gtk2 \
        python-gtk2-dev \
        python-matplotlib \
        python-mock \
        python-numpy \
        python-pip \
        python-prettytable \
        pkg-config \
        python-pyfits \
        python-pyraf \
        python-requests \
        python-scipy \
        python-setuptools \
        python-subprocess32 \
        python-uncertainties \
        python-unittest2 \
        sextractor \
        astrometry.net \
        wget \
        xauth \
        xvfb

    cat > /usr/local/bin/mpirun <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/bin/mpirun.openmpi --allow-run-as-root --mca plm isolated "\$@"
WRAP
    chmod +x /usr/local/bin/mpirun

    # Build Montage from source with MPI-enabled executables. The Ubuntu
    # package provides the serial toolkit only; LEMON's --cores flag expects
    # binaries such as mProjExecMPI to exist.
    rm -rf /tmp/montage-src
    git clone --branch "${MONTAGE_REF}" --single-branch https://github.com/Caltech-IPAC/Montage.git /tmp/montage-src \
      || { git clone https://github.com/Caltech-IPAC/Montage.git /tmp/montage-src && git -C /tmp/montage-src checkout "${MONTAGE_REF}"; }
    sed -i \
        -e 's/^# MPICC  =.*/MPICC  = mpicc/' \
        -e 's/^# BINS =.*/BINS   = \$(SBINS) mProjExecMPI mFitExecMPI mDiffExecMPI/' \
        /tmp/montage-src/Montage/Makefile
    python - <<'PY'
from __future__ import print_function

patches = {
    "/tmp/montage-src/Montage/checkHdr.c": (
        "extern FILE *fout;\n",
        "FILE *fout;\n",
    ),
    "/tmp/montage-src/Montage/mHdrCheck.c": (
        "FILE *fout;\n",
        "extern FILE *fout;\n",
    ),
}

for path, (needle, replacement) in patches.items():
    with open(path) as fh:
        data = fh.read()
    if needle not in data:
        raise SystemExit("Failed to patch %s: expected text not found" % path)
    with open(path, "w") as fh:
        fh.write(data.replace(needle, replacement, 1))
PY
    make -C /tmp/montage-src
    make -C /tmp/montage-src install
    mv /usr/local/bin/mProjExec /usr/local/bin/mProjExec.real
    cat > /usr/local/bin/mProjExec <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
args=("\$@")
have_status=0
have_debug=0
for arg in "\${args[@]}"; do
    if [[ "\${arg}" == "-s" ]]; then
        have_status=1
    elif [[ "\${arg}" == "-d" ]]; then
        have_debug=1
    fi
done
if [[ -n "\${LEMON_MPROJEXEC_STATUS:-}" && "\${have_status}" == "0" ]]; then
    args=("-s" "\${LEMON_MPROJEXEC_STATUS}" "\${args[@]}")
    mkdir -p "\$(dirname "\${LEMON_MPROJEXEC_STATUS}")"
fi
if [[ "\${LEMON_MPROJEXEC_DEBUG:-0}" == "1" && "\${have_debug}" == "0" ]]; then
    args=("-d" "\${args[@]}")
fi
exec /usr/local/bin/mProjExec.real "\${args[@]}"
WRAP
    chmod +x /usr/local/bin/mProjExec
    cat > /usr/local/bin/mBgExecMPI <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
rank="\${OMPI_COMM_WORLD_RANK:-\${PMI_RANK:-\${MPI_RANKID:-0}}}"
if [[ "\${rank}" == "0" ]]; then
    exec /usr/local/bin/mBgExec "\$@"
fi
exit 0
WRAP
    chmod +x /usr/local/bin/mBgExecMPI
    rm -rf /tmp/montage-src

    # These Python 2 packages are not available as Ubuntu packages here, but
    # they are required by LEMON runtime and tests.
    python -m pip install --no-cache-dir 'absl-py==0.9.0'
    # Force a source build so GTK2 Matplotlib extensions (_backend_gdk,
    # _gtkagg) are present for Juicer.
    python -m pip install --no-cache-dir --no-binary=:all: 'matplotlib==1.5.3'
    python -m pip install --no-cache-dir 'montage-wrapper==0.9.9'

    # Fail the build if the Montage CLI expected by montage-wrapper is not
    # actually present in the final runtime image.
    for cmd in mImgtbl mMakeHdr mProjExec mAdd mConvert mpirun mProjExecMPI mDiffExecMPI mFitExecMPI mBgExecMPI; do
        command -v "\$cmd" >/dev/null 2>&1 || {
            echo "Missing required runtime executable: \$cmd" >&2
            exit 1
        }
    done
    python - <<'PY'
import os
import subprocess
import montage_wrapper

required = [
    "mImgtbl", "mMakeHdr", "mProjExec", "mAdd", "mConvert",
    "mpirun", "mProjExecMPI", "mDiffExecMPI", "mFitExecMPI", "mBgExecMPI",
]
missing = []
for name in required:
    try:
        subprocess.check_call(
            ["bash", "-lc", "command -v %s >/dev/null 2>&1" % name]
        )
    except subprocess.CalledProcessError:
        missing.append(name)

if missing:
    raise SystemExit("Montage runtime check failed: missing %s" % ", ".join(missing))

print("Validated montage-wrapper runtime from %s" % montage_wrapper.__file__)
PY

    git clone --branch "${LEMON_REF}" --single-branch https://github.com/vterron/lemon.git /opt/lemon \
      || { git clone https://github.com/vterron/lemon.git /opt/lemon && git -C /opt/lemon checkout "${LEMON_REF}"; }

    # LEMON assumes that --cores > 1 implies MPI-enabled Montage binaries are
    # installed, so keep a defensive runtime fallback in case the MPI tools are
    # missing from a custom image or broken at runtime.
    python - <<'PY'
from __future__ import print_function
from distutils.spawn import find_executable

path = "/opt/lemon/mosaic.py"
with open(path) as fh:
    data = fh.read()

import_needle = "import shutil\n"
import_replacement = "import shutil\nimport subprocess\nfrom distutils.spawn import find_executable\n"
needle = """    if options.ncores > 1:\n        kwargs[\"mpi\"] = True  # use MPI whenever possible\n        kwargs[\"n_proc\"] = options.ncores  # number of MPI processes\n"""
replacement = """    if options.ncores > 1:\n        mpi_ready = find_executable(\"mProjExecMPI\") is not None\n        if mpi_ready:\n            mpi_ready = not subprocess.call([\n                \"bash\",\n                \"-lc\",\n                \"mpirun -n 1 /bin/true >/dev/null 2>&1\",\n            ])\n        if mpi_ready:\n            kwargs[\"mpi\"] = True  # use MPI whenever possible\n            kwargs[\"n_proc\"] = options.ncores  # number of MPI processes\n        else:\n            print \"%sWarning: MPI Montage support is not usable in this runtime; falling back to serial mosaic mode.\" % style.prefix\n"""
workdir_needle = "    montage.mosaic(input_dir, output_dir, **kwargs)\n"
workdir_replacement = """    work_root = os.environ.get(\"LEMON_MOSAIC_WORKROOT\")\n    if work_root:\n        if not os.path.isdir(work_root):\n            os.makedirs(work_root)\n        kwargs[\"work_dir\"] = tempfile.mkdtemp(dir=work_root, suffix=suffix + \"_work\")\n\n    montage.mosaic(input_dir, output_dir, **kwargs)\n"""
preflight_needle = """    # Map each filter to a list of FITSImage objects\n    files = fitsimage.InputFITSFiles()\n\n    msg = \"%sMaking sure the %d input paths are FITS images...\"\n    print msg % (style.prefix, len(input_paths))\n\n    util.show_progress(0.0)\n    for index, path in enumerate(input_paths):\n        # fitsimage.FITSImage.__init__() raises fitsimage.NonStandardFITS if\n        # one of the paths is not a standard-conforming FITS file.\n        try:\n            img = fitsimage.FITSImage(path)\n\n            # If we do not need to know the photometric filter (because the\n            # --filter was not given) do not read it from the FITS header.\n            # Instead, use None. This means that 'files', a dictionary, will\n            # only have a key, None, mapping to all the input FITS images.\n\n            if options.filter:\n                pfilter = img.pfilter(options.filterk)\n            else:\n                pfilter = None\n\n            files[pfilter].append(img)\n\n        except fitsimage.NonStandardFITS:\n            print\n            msg = \"'%s' is not a standard FITS file\"\n            raise fitsimage.NonStandardFITS(msg % path)\n\n        percentage = (index + 1) / len(input_paths) * 100\n        util.show_progress(percentage)\n    print  # progress bar doesn't include newline\n\n    # The --filter option allows the user to specify which FITS files, among\n    # all those received as input, must be combined: only those images taken\n    # in the options.filter photometric filter.\n"""
preflight_replacement = """    # Map each filter to a list of FITSImage objects\n    files = fitsimage.InputFITSFiles()\n    skip_preflight = os.environ.get(\"LEMON_MOSAIC_SKIP_PREFLIGHT\") == \"1\"\n\n    if skip_preflight and not options.filter:\n        class _InputPath(object):\n            def __init__(self, path):\n                self.path = path\n\n        print \"%sSkipping FITS/WCS preflight scan and deferring validation to Montage.\" % style.prefix\n        for path in sorted(input_paths):\n            files[None].append(_InputPath(path))\n    else:\n        msg = \"%sMaking sure the %d input paths are FITS images...\"\n        print msg % (style.prefix, len(input_paths))\n\n        util.show_progress(0.0)\n        for index, path in enumerate(input_paths):\n            # fitsimage.FITSImage.__init__() raises fitsimage.NonStandardFITS if\n            # one of the paths is not a standard-conforming FITS file.\n            try:\n                img = fitsimage.FITSImage(path)\n\n                # If we do not need to know the photometric filter (because the\n                # --filter was not given) do not read it from the FITS header.\n                # Instead, use None. This means that 'files', a dictionary, will\n                # only have a key, None, mapping to all the input FITS images.\n\n                if options.filter:\n                    pfilter = img.pfilter(options.filterk)\n                else:\n                    pfilter = None\n\n                files[pfilter].append(img)\n\n            except fitsimage.NonStandardFITS:\n                print\n                msg = \"'%s' is not a standard FITS file\"\n                raise fitsimage.NonStandardFITS(msg % path)\n\n            percentage = (index + 1) / len(input_paths) * 100\n            util.show_progress(percentage)\n        print  # progress bar doesn't include newline\n\n    # The --filter option allows the user to specify which FITS files, among\n    # all those received as input, must be combined: only those images taken\n    # in the options.filter photometric filter.\n"""
wcs_needle = """    for img in files:\n        # May raise NoWCSInformationError\n        img.center_wcs()\n"""
wcs_replacement = """    if not skip_preflight:\n        for img in files:\n            # May raise NoWCSInformationError\n            img.center_wcs()\n"""

if import_needle not in data:
    raise SystemExit("Failed to patch /opt/lemon/mosaic.py: expected import not found")
if needle not in data:
    raise SystemExit("Failed to patch /opt/lemon/mosaic.py: expected block not found")
if workdir_needle not in data:
    raise SystemExit("Failed to patch /opt/lemon/mosaic.py: expected montage.mosaic call not found")
if preflight_needle not in data:
    raise SystemExit("Failed to patch /opt/lemon/mosaic.py: expected preflight block not found")
if wcs_needle not in data:
    raise SystemExit("Failed to patch /opt/lemon/mosaic.py: expected WCS block not found")

with open(path, "w") as fh:
    fh.write(
        data.replace(import_needle, import_replacement, 1)
            .replace(needle, replacement, 1)
            .replace(preflight_needle, preflight_replacement, 1)
            .replace(wcs_needle, wcs_replacement, 1)
            .replace(workdir_needle, workdir_replacement, 1)
    )
PY

    python - <<'PY'
from __future__ import print_function

path = "/opt/lemon/fitsimage.py"
with open(path) as fh:
    data = fh.read()

needle = """                try:\n                    type_ = pyfits.info(self.path, output=False)[0][2]\n                    if type_ == \"NonstandardHDU\":\n                        # 'SIMPLE' exists but does not equal 'T'\n                        msg = \"%s: value of 'SIMPLE' keyword is not 'T'\"\n                        raise NonStandardFITS(msg % self.path)\n\n                except AttributeError as e:\n                    # 'SIMPLE' keyword does not exist\n                    error_msg = \"'_ValidHDU' object has no attribute '_summary'\"\n                    assert error_msg in str(e)\n                    msg = \"%s: 'SIMPLE' keyword missing from header\"\n                    raise NonStandardFITS(msg % self.path)\n"""
replacement = """                # PyFITS 3.3+ reopens and re-parses the file in pyfits.info().\n                # For large campaigns this turns FITS validation into a major\n                # startup bottleneck. If pyfits.open() succeeded and the primary\n                # HDU is readable, trust that result and avoid the second pass.\n"""

if needle not in data:
    raise SystemExit("Failed to patch /opt/lemon/fitsimage.py: expected validation block not found")

with open(path, "w") as fh:
    fh.write(data.replace(needle, replacement, 1))
PY

    chmod +x /opt/lemon/lemon
    mkdir -p /opt/lemon/pyraf
    mkdir -p /tmp/lemon-iraf/home /tmp/lemon-iraf/uparm /tmp/lemon-iraf/imdir /tmp/lemon-iraf/cache
    sed \
        -e 's+U_TERM+xgterm+' \
        -e 's+U_HOME+/tmp/lemon-iraf/home/+' \
        -e 's+U_UPARM+/tmp/lemon-iraf/uparm/+' \
        -e 's+U_IMDIR+/tmp/lemon-iraf/imdir/+' \
        -e 's+U_CACHEDIR+/tmp/lemon-iraf/cache/+' \
        -e 's+U_USER+lemon+' \
        /usr/lib/iraf/pkg/cl/login.cl > /opt/lemon/login.cl

    cat > /usr/local/bin/lemon <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
runtime_root="\${LEMON_IRAF_RUNTIME:-/tmp/lemon-iraf}"
mkdir -p "\${runtime_root}/home" "\${runtime_root}/uparm" "\${runtime_root}/imdir" "\${runtime_root}/cache"
export HOME="\${runtime_root}/home"
export OMPI_ALLOW_RUN_AS_ROOT="\${OMPI_ALLOW_RUN_AS_ROOT:-1}"
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM="\${OMPI_ALLOW_RUN_AS_ROOT_CONFIRM:-1}"
export OMPI_MCA_plm="\${OMPI_MCA_plm:-isolated}"
export PYRAF_NO_DISPLAY="\${PYRAF_NO_DISPLAY:-1}"
export LEMON_MPROJEXEC_DEBUG="\${LEMON_MPROJEXEC_DEBUG:-0}"
export LEMON_MPROJEXEC_STATUS="\${LEMON_MPROJEXEC_STATUS:-}"
export LEMON_MOSAIC_WORKROOT="\${LEMON_MOSAIC_WORKROOT:-/tmp/lemon-mosaic-work}"
exec python /opt/lemon/lemon "\$@"
WRAP
    chmod +x /usr/local/bin/lemon
    cat > /usr/local/bin/juicer <<'WRAP'
#!/usr/bin/env bash
exec /usr/local/bin/lemon juicer "\$@"
WRAP
    chmod +x /usr/local/bin/juicer

    apt-get clean
    rm -rf /var/lib/apt/lists/*
    rm -rf /root/.cache/pip

%runscript
    exec /usr/local/bin/lemon "\$@"
EOF

echo "Building ${IMAGE_NAME} from LEMON ref ${LEMON_REF}" >&2
echo "Temporary build root: ${BUILD_TMP_ROOT}" >&2
echo "Temporary cache root: ${BUILD_CACHE_ROOT}" >&2
export APPTAINER_TMPDIR="${BUILD_TMP_ROOT}"
export APPTAINER_CACHEDIR="${BUILD_CACHE_ROOT}"
build_args=()
if [[ -n "${BUILD_ARGS}" ]]; then
    read -r -a build_args <<< "${BUILD_ARGS}"
fi
set -x
apptainer build \
    "${build_mode[@]}" \
    --force \
    --disable-cache \
    --mksquashfs-args "${MKSQUASHFS_ARGS}" \
    "${build_args[@]}" \
    "${IMAGE_NAME}" \
    "${def_file}"
