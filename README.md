# LEMON Apptainer

Apptainer build and run helpers for [LEMON](https://github.com/vterron/lemon), including the Juicer GUI.

## Contents

- `build_lemon_apptainer.sh`
  Builds an Apptainer image with LEMON, Juicer, IRAF, Montage, SExtractor, Astrometry.net, and the Python 2 stack required by LEMON.
- `run_lemon.bash`
  Runs the complete reduction pipeline for one dataset:
  `mosaic -> photometry -> diffphot`
- `run_lemon_sequential.bash`
  Runs the same reduction pipeline with the sequential image and serial mosaic mode.
- `run_juicer.bash`
  Opens Juicer on the generated `curves.LEMONdB` database.
- `run_juicer_sequential.bash`
  Opens Juicer explicitly with the sequential image.

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

Run explicitly in sequential mode:

```bash
./run_lemon_sequential.bash
./run_lemon_sequential.bash HAT-P-32
./run_lemon_sequential.bash HAT-P-32 mosaic
```

Run a different object:

```bash
./run_lemon.bash HAT-P-32
```

Run only one stage:

```bash
./run_lemon.bash mosaic
./run_lemon.bash HAT-P-32 photometry
./run_lemon.bash HAT-P-32 diffphot
```

Control mosaic parallelism:

```bash
MOSAIC_CORES=8 ./run_lemon.bash
```

Set execution timeout:

```bash
LEMON_TIMEOUT=2400 ./run_lemon.bash     # 40 minutes (default, recommended)
LEMON_TIMEOUT=3000 ./run_lemon.bash     # 50 minutes (for extremely large datasets)
LEMON_TIMEOUT=0 ./run_lemon.bash        # No timeout (unlimited)
```

Useful variables:

- `OBJECT` dataset name, default `HAT-P-16`
- `ROOT_DIR` data root
- `MOSAIC_CORES` passed to `lemon mosaic --cores`, default `4`
- `LEMON_TIMEOUT` execution timeout in seconds, default `2400` (40 minutes)

Positional arguments:

- first argument: optional object name
- second argument: optional stage, one of `mosaic`, `photometry`, `diffphot`
- if only one argument is given and it is one of those stage names, it is treated as the stage
- if no stage is given, the full pipeline runs

Sequential pipeline notes:

- `run_lemon_sequential.bash` uses `lemon-juicer_sequential.sif`
- it always runs `lemon mosaic` with `--cores 1`

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

Launch Juicer explicitly with the sequential image:

```bash
./run_juicer_sequential.bash
./run_juicer_sequential.bash HAT-P-32
```

Launch Juicer for a different object:

```bash
./run_juicer.bash HAT-P-32
```

Useful variables:

- `OBJECT` dataset name, default `HAT-P-16`
- `ROOT_DIR` data root
- `LEMON_IMAGE` custom image path

Juicer requires:

- `DISPLAY` to be set
- `/tmp/.X11-unix` to be accessible

## Image Override

The launchers use these default images from the same directory:

- `run_lemon.bash` -> `lemon-juicer.sif`
- `run_lemon_sequential.bash` -> `lemon-juicer_sequential.sif`
- `run_juicer.bash` -> `lemon-juicer_sequential.sif`
- `run_juicer_sequential.bash` -> `lemon-juicer_sequential.sif`

You can override any of them with `LEMON_IMAGE`:

```bash
LEMON_IMAGE=/path/to/custom.sif ./run_lemon.bash
LEMON_IMAGE=/path/to/custom.sif ./run_lemon_sequential.bash
LEMON_IMAGE=/path/to/custom.sif ./run_juicer.bash
LEMON_IMAGE=/path/to/custom.sif ./run_juicer_sequential.bash
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

- `run_lemon.bash` appears to hang at startup
  - cause: MPI initialization probe (`mpirun`) is slow or unresponsive
  - fix: this is handled automatically with a 5-second timeout; if it still hangs, check MPI configuration or disable MPI entirely by setting `MOSAIC_CORES=1`

- `run_lemon.bash HAT-P-16` produces no output (full 518-file dataset)
  - cause: Processing time for 518 files (~1100+ seconds) may exceed timeout if reduced
  - default 1800-second timeout should now work: `./run_lemon.bash HAT-P-16`
  - if still needed, increase timeout: `LEMON_TIMEOUT=2400 ./run_lemon.bash HAT-P-16`
  - or use serial mode (slower): `MOSAIC_CORES=1 ./run_lemon.bash HAT-P-16`
  - processing times: 30 files (~30s), 50 files (~40s), 100 files (~60s), 150 files (~120s), 518 files (~1000-1200s)

- `run_lemon.bash` times out during mosaic processing with large datasets
  - cause: Processing time scales non-linearly with file count
  - workaround 1: reduce dataset size by selecting a subset of frames
  - workaround 2: increase timeout: `LEMON_TIMEOUT=1800 ./run_lemon.bash OBJECT mosaic`
  - workaround 3: use serial mosaic mode: `MOSAIC_CORES=1 LEMON_TIMEOUT=1800 ./run_lemon.bash`
  - note: orphaned `mpirun` processes are automatically cleaned up when the script exits

- Stray `mpirun` processes consuming CPU
  - cause: if previous runs were interrupted with SIGKILL, orphaned processes may remain
  - fix: cleanup is now automatic, but manual cleanup can be done with `pkill -9 mpirun`

- Juicer fails to start with display errors
  - confirm `DISPLAY` is set on the host
  - confirm `/tmp/.X11-unix` exists and is accessible
  - if needed, allow local X11 access before launching, for example with `xhost +local:`

- `run_lemon.bash` cannot find input data
  - supported layouts are `in/out` and `input/output`
  - set `ROOT_DIR` explicitly if your data is not under the repo-local `./data`
