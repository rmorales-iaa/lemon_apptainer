# LEMON Apptainer

Apptainer build and run helpers for [LEMON](https://github.com/vterron/lemon), including the Juicer GUI.

## Contents

- `build_lemon_juicer_apptainer.sh`
  Builds an Apptainer image with LEMON, Juicer, IRAF, Montage, SExtractor, Astrometry.net, and the Python 2 stack required by LEMON.
- `run_lemon.bash`
  Runs the reduction pipeline for one dataset:
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
./build_lemon_juicer_apptainer.sh
```

Build a custom image name:

```bash
./build_lemon_juicer_apptainer.sh lemon-juicer.sif
```

Build a specific LEMON revision:

```bash
LEMON_REF=master ./build_lemon_juicer_apptainer.sh
```

Build notes:

- build temp and cache default to local storage under `/var/tmp/.../lemon_apptainer`
- this avoids `dpkg` hangs seen when Apptainer temp files are placed on NFS
- override with `WORK_ROOT`, `BUILD_TMP_ROOT`, or `BUILD_CACHE_ROOT` if needed
- the recipe forces a source build of `matplotlib==1.5.3` so Juicer gets the legacy GTK2 modules it needs

## Data Layout

Both launchers accept either of these layouts:

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

- use `./data` next to the scripts when that dataset exists there
- otherwise fall back to `/home/rafa/apps/lemon/lemon_apptainer/data`

Example layout:

```text
./data/
├── in/
│   └── HAT-P-16/
│       ├── frame001.fits
│       ├── frame002.fits
│       └── ...
└── out/
    └── HAT-P-16/
```

## Run The Pipeline

Run the default dataset:

```bash
./run_lemon.bash
```

Run a different object:

```bash
./run_lemon.bash HAT-P-32
```

Run only one stage:

```bash
./run_lemon.bash HAT-P-32 mosaic
./run_lemon.bash HAT-P-32 photometry
./run_lemon.bash HAT-P-32 diffphot
```

Control mosaic parallelism:

```bash
MOSAIC_CORES=8 ./run_lemon.bash HAT-P-16
```

Set execution timeout:

```bash
LEMON_TIMEOUT=2400 ./run_lemon.bash HAT-P-16   # default: 40 minutes
LEMON_TIMEOUT=3000 ./run_lemon.bash HAT-P-16   # larger datasets
LEMON_TIMEOUT=0 ./run_lemon.bash HAT-P-16      # disable timeout
```

Useful variables:

- `OBJECT` dataset name, default `HAT-P-16`
- `ROOT_DIR` data root
- `MOSAIC_CORES` passed to `lemon mosaic --cores`, default `4`
- `LEMON_TIMEOUT` execution timeout in seconds, default `2400`
- `LEMON_IMAGE` override image path

This produces:

- `mosaic.fits`
- `phot.LEMONdB`
- `curves.LEMONdB`

inside:

```text
$ROOT_DIR/out/$OBJECT/
```

## HAT-P-16 Example

Command-by-command example for `HAT-P-16`:

1. Check input data exists.

```bash
ls -lh ./data/in/HAT-P-16
```

2. Run full pipeline with current default timeout.

```bash
./run_lemon.bash HAT-P-16
```

3. If dataset is slow on your machine, run again with more time.

```bash
LEMON_TIMEOUT=3000 ./run_lemon.bash HAT-P-16
```

4. If MPI causes trouble, force serial mosaic mode.

```bash
MOSAIC_CORES=1 LEMON_TIMEOUT=3000 ./run_lemon.bash HAT-P-16
```

5. Check output files.

```bash
ls -lh ./data/out/HAT-P-16
```

6. Run stages one by one if you want manual control.

```bash
./run_lemon.bash HAT-P-16 mosaic
./run_lemon.bash HAT-P-16 photometry
./run_lemon.bash HAT-P-16 diffphot
```

7. Open result in Juicer.

```bash
./run_juicer.bash HAT-P-16
```

Expected outputs:

```text
./data/out/HAT-P-16/mosaic.fits
./data/out/HAT-P-16/phot.LEMONdB
./data/out/HAT-P-16/curves.LEMONdB
```

## Run Juicer

After `curves.LEMONdB` exists, launch Juicer with:

```bash
./run_juicer.bash
./run_juicer.bash HAT-P-16
```

Useful variables:

- `OBJECT` dataset name, default `HAT-P-16`
- `ROOT_DIR` data root
- `LEMON_IMAGE` custom image path

Juicer requires:

- `DISPLAY` to be set
- `/tmp/.X11-unix` to be accessible

## Image Override

The launchers use `/mnt/uxmal_groups/common_data/apps/lemon_apptainer_images/lemon-juicer.sif` by default.

If that image is not present, both launchers fall back to `./lemon-juicer-test.sif` when available.

Override the image explicitly with `LEMON_IMAGE`:

```bash
LEMON_IMAGE=/path/to/custom.sif ./run_lemon.bash HAT-P-16
LEMON_IMAGE=/path/to/custom.sif ./run_juicer.bash HAT-P-16
```

## Notes

- the image is based on `ubuntu:18.04` because LEMON and Juicer depend on an older Python 2 / GTK2 stack
- `run_lemon.bash` validates the runtime at startup and creates a temporary IRAF home under `./tmp`
- `run_lemon.bash` removes the target output directory before a full run or `mosaic` stage
- if MPI Montage support is not usable in the container runtime, `run_lemon.bash` automatically falls back to serial mosaic mode

## Troubleshooting

- Build appears to hang during `apt` or `dpkg`
  - keep `WORK_ROOT`, `BUILD_TMP_ROOT`, and `BUILD_CACHE_ROOT` on local storage such as `/var/tmp`

- `run_lemon.bash` appears to hang at startup
  - MPI probing is bounded by a 5-second timeout
  - if needed, force serial mode with `MOSAIC_CORES=1`

- `run_lemon.bash HAT-P-16` takes a long time
  - this is normal for the full dataset
  - if you hit the timeout, increase it: `LEMON_TIMEOUT=3000 ./run_lemon.bash HAT-P-16`
  - if MPI is problematic, use `MOSAIC_CORES=1 ./run_lemon.bash HAT-P-16`

- Juicer fails to start with display errors
  - confirm `DISPLAY` is set on the host
  - confirm `/tmp/.X11-unix` exists and is accessible
  - if needed, allow local X11 access before launching, for example with `xhost +local:`

- `run_lemon.bash` cannot find input data
  - supported layouts are `in/out` and `input/output`
  - set `ROOT_DIR` explicitly if your data is not under repo-local `./data`
