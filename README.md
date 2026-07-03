# LEMON Apptainer

Apptainer build and run helpers for [LEMON](https://github.com/vterron/lemon), including the Juicer GUI.

## Contents

- `build_lemon_apptainer.sh`
  Builds an Apptainer image with LEMON, Juicer, IRAF, Montage, SExtractor, Astrometry.net, and the Python 2 stack required by LEMON.
- `run_lemon.bash`
  Runs the complete reduction pipeline for one dataset:
  `mosaic -> photometry -> diffphot`
- `run_juicer.bash`
  Opens Juicer on the generated `curves.LEMONdB` database.

## Requirements

- Linux host with `apptainer`
- `fakeroot` support for unprivileged builds and runs
- X11 available on the host for Juicer

## Build

Build the default image:

```bash
./build_lemon_apptainer.sh
```

Build a custom image name:

```bash
./build_lemon_apptainer.sh lemon-juicer.sif
```

Build a specific LEMON revision:

```bash
LEMON_REF=master ./build_lemon_apptainer.sh
```

Build notes:

- build temp and cache default to local storage under `/var/tmp/.../lemon_apptainer`
- this avoids `dpkg` hangs seen when Apptainer temp files are placed on NFS
- override with `WORK_ROOT`, `BUILD_TMP_ROOT`, or `BUILD_CACHE_ROOT` if needed

Important implementation detail:

- the recipe forces a source build of `matplotlib==1.5.3`
- this is required so Juicer gets the legacy GTK2 modules `_backend_gdk.so` and `_gtkagg.so`
- the recipe now validates the Montage CLI (`mImgtbl`, `mMakeHdr`, `mProjExec`, `mAdd`, `mConvert`) during build so missing mosaic executables fail the image build immediately
- the Ubuntu `montage` package does not ship MPI binaries such as `mProjExecMPI`; the image now patches LEMON so `--cores > 1` falls back to serial mosaic mode instead of crashing

## Data Layout

Both runner scripts accept two directory layouts:

```text
$ROOT_DIR/in/$OBJECT/
$ROOT_DIR/out/$OBJECT/
```

or:

```text
$ROOT_DIR/input/$OBJECT/
$ROOT_DIR/output/$OBJECT/
```

Default root selection:

```bash
OBJECT="HAT-P-16"
ROOT_DIR="./data"
```

If `ROOT_DIR` is not set:

- the scripts first use `./data` next to the scripts if it exists
- otherwise they fall back to `/home/rafa/apps/lemon/lemon_apptainer/data`

Example layout:

```text
/path/to/data/
├── in/
│   └── HAT-P-16/
│       ├── file1.fits
│       ├── file2.fits
│       └── ...
└── out/
    └── HAT-P-16/
```

## Run The Pipeline

Run with defaults:

```bash
./run_lemon.bash
```

Control mosaic parallelism:

```bash
MOSAIC_CORES=8 ./run_lemon.bash
```

Useful variables:

- `OBJECT` dataset name, default `HAT-P-16`
- `ROOT_DIR` data root
- `MOSAIC_CORES` passed to `lemon mosaic --cores`, default `4`

This produces:

- `mosaic.fits`
- `phot.LEMONdB`
- `curves.LEMONdB`

inside:

```text
$ROOT_DIR/out/$OBJECT/
```

## Run Juicer

After `curves.LEMONdB` exists, launch Juicer with:

```bash
./run_juicer.bash
```

Useful variables:

- `OBJECT` dataset name, default `HAT-P-16`
- `ROOT_DIR` data root
- `LEMON_IMAGE` custom image path

Juicer requires:

- `DISPLAY` to be set
- `/tmp/.X11-unix` to be accessible

## Image Override

Both runner scripts use `lemon-juicer.sif` in the same directory by default.
You can override that with `LEMON_IMAGE`:

```bash
LEMON_IMAGE=/path/to/custom.sif ./run_lemon.bash
LEMON_IMAGE=/path/to/custom.sif ./run_juicer.bash
```

## Notes

- the image is based on `ubuntu:18.04` because LEMON and Juicer depend on an older Python 2 / GTK2 stack
- build temp and cache directories default to local `/var/tmp/.../lemon_apptainer`
- `mksquashfs` is limited to one processor by default because parallel packaging was unstable in this environment
- Juicer startup may spend some time building the Matplotlib font cache on first launch
- `run_lemon.bash` now validates Montage and IRAF at startup instead of installing packages into a temporary writable layer

## Troubleshooting

- Build appears to hang during `apt` or `dpkg`
  - cause: Apptainer temporary build state is on NFS
  - fix: keep `WORK_ROOT`, `BUILD_TMP_ROOT`, and `BUILD_CACHE_ROOT` on local storage such as `/var/tmp`

- Juicer fails to start with display errors
  - confirm `DISPLAY` is set on the host
  - confirm `/tmp/.X11-unix` exists and is accessible
  - if needed, allow local X11 access before launching, for example with `xhost +local:`

- `run_lemon.bash` cannot find input data
  - supported layouts are `in/out` and `input/output`
  - set `ROOT_DIR` explicitly if your data is not under the repo-local `./data`
