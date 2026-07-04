# Host Dependencies

This repository builds and runs LEMON through Apptainer on the host. The
container image carries the astronomy stack; the host only needs the container
runtime, rootless build support, FUSE helpers, and optional X11 support for
Juicer.

## Debian Host

Recommended packages:

```bash
sudo apt-get update
sudo apt-get install -y \
  apptainer \
  fakeroot \
  uidmap \
  fuse3 \
  fuse-overlayfs \
  squashfuse \
  xauth \
  x11-xserver-utils
```

Notes:

- `uidmap` provides `newuidmap` and `newgidmap` for rootless `--fakeroot`.
- `xauth` and `x11-xserver-utils` are only needed for Juicer.
- On some Debian releases the `apptainer` package may already pull some FUSE
  helpers; keeping them explicit avoids host-to-host surprises.

## Fedora Host

Recommended packages:

```bash
sudo dnf install -y \
  apptainer \
  fakeroot \
  shadow-utils \
  fuse3 \
  fuse-overlayfs \
  squashfuse \
  xauth \
  xhost
```

Notes:

- `shadow-utils` provides `newuidmap` and `newgidmap`.
- `xauth` and `xhost` are only needed for Juicer.
- Fedora's `apptainer` package may bundle some helper binaries internally, but
  the explicit package list keeps the host setup predictable.

## Host Configuration

These are required regardless of distro:

- Unprivileged user namespaces must be enabled.
- The user running builds should have entries in `/etc/subuid` and
  `/etc/subgid`.
- `apptainer config fakeroot --add $USER` can be used by an administrator to
  provision those mappings.
- Build temp and cache directories should be on local storage, not NFS.
- For Juicer, `DISPLAY` must be set and `/tmp/.X11-unix` must be accessible.

## Quick Checks

Verify the host has the minimum required commands:

```bash
command -v apptainer
command -v fakeroot
command -v newuidmap
command -v newgidmap
command -v fuse-overlayfs
command -v squashfuse_ll || command -v squashfuse
```

Verify fakeroot mappings exist:

```bash
grep "^$USER:" /etc/subuid
grep "^$USER:" /etc/subgid
```

Verify Juicer X11 access:

```bash
echo "$DISPLAY"
test -S /tmp/.X11-unix/X0 || ls /tmp/.X11-unix
```
