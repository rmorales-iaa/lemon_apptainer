#!/usr/bin/env python
from __future__ import print_function


def replace_once(data, needle, replacement):
    if needle in data:
        return data.replace(needle, replacement, 1)
    return data


def patch_fitsimage():
    path = "/opt/lemon/fitsimage.py"
    with open(path) as fh:
        data = fh.read()

    needle = """                try:\n                    type_ = pyfits.info(self.path, output=False)[0][2]\n                    if type_ == \"NonstandardHDU\":\n                        # 'SIMPLE' exists but does not equal 'T'\n                        msg = \"%s: value of 'SIMPLE' keyword is not 'T'\"\n                        raise NonStandardFITS(msg % self.path)\n\n                except AttributeError as e:\n                    # 'SIMPLE' keyword does not exist\n                    error_msg = \"'_ValidHDU' object has no attribute '_summary'\"\n                    assert error_msg in str(e)\n                    msg = \"%s: 'SIMPLE' keyword missing from header\"\n                    raise NonStandardFITS(msg % self.path)\n"""
    replacement = """                # PyFITS 3.3+ reopens and re-parses the file in pyfits.info().\n                # For large campaigns this turns FITS validation into a major\n                # startup bottleneck. If pyfits.open() succeeded and the primary\n                # HDU is readable, trust that result and avoid the second pass.\n"""

    new_data = replace_once(data, needle, replacement)
    if new_data != data:
        with open(path, "w") as fh:
            fh.write(new_data)


def patch_mosaic():
    path = "/opt/lemon/mosaic.py"
    with open(path) as fh:
        data = fh.read()

    preflight_needle = """    # Map each filter to a list of FITSImage objects\n    files = fitsimage.InputFITSFiles()\n\n    msg = \"%sMaking sure the %d input paths are FITS images...\"\n    print msg % (style.prefix, len(input_paths))\n\n    util.show_progress(0.0)\n    for index, path in enumerate(input_paths):\n        # fitsimage.FITSImage.__init__() raises fitsimage.NonStandardFITS if\n        # one of the paths is not a standard-conforming FITS file.\n        try:\n            img = fitsimage.FITSImage(path)\n\n            # If we do not need to know the photometric filter (because the\n            # --filter was not given) do not read it from the FITS header.\n            # Instead, use None. This means that 'files', a dictionary, will\n            # only have a key, None, mapping to all the input FITS images.\n\n            if options.filter:\n                pfilter = img.pfilter(options.filterk)\n            else:\n                pfilter = None\n\n            files[pfilter].append(img)\n\n        except fitsimage.NonStandardFITS:\n            print\n            msg = \"'%s' is not a standard FITS file\"\n            raise fitsimage.NonStandardFITS(msg % path)\n\n        percentage = (index + 1) / len(input_paths) * 100\n        util.show_progress(percentage)\n    print  # progress bar doesn't include newline\n\n    # The --filter option allows the user to specify which FITS files, among\n    # all those received as input, must be combined: only those images taken\n    # in the options.filter photometric filter.\n"""
    preflight_replacement = """    # Map each filter to a list of FITSImage objects\n    files = fitsimage.InputFITSFiles()\n    skip_preflight = os.environ.get(\"LEMON_MOSAIC_SKIP_PREFLIGHT\") == \"1\"\n\n    if skip_preflight and not options.filter:\n        class _InputPath(object):\n            def __init__(self, path):\n                self.path = path\n\n        print \"%sSkipping FITS/WCS preflight scan and deferring validation to Montage.\" % style.prefix\n        for path in sorted(input_paths):\n            files[None].append(_InputPath(path))\n    else:\n        msg = \"%sMaking sure the %d input paths are FITS images...\"\n        print msg % (style.prefix, len(input_paths))\n\n        util.show_progress(0.0)\n        for index, path in enumerate(input_paths):\n            # fitsimage.FITSImage.__init__() raises fitsimage.NonStandardFITS if\n            # one of the paths is not a standard-conforming FITS file.\n            try:\n                img = fitsimage.FITSImage(path)\n\n                # If we do not need to know the photometric filter (because the\n                # --filter was not given) do not read it from the FITS header.\n                # Instead, use None. This means that 'files', a dictionary, will\n                # only have a key, None, mapping to all the input FITS images.\n\n                if options.filter:\n                    pfilter = img.pfilter(options.filterk)\n                else:\n                    pfilter = None\n\n                files[pfilter].append(img)\n\n            except fitsimage.NonStandardFITS:\n                print\n                msg = \"'%s' is not a standard FITS file\"\n                raise fitsimage.NonStandardFITS(msg % path)\n\n            percentage = (index + 1) / len(input_paths) * 100\n            util.show_progress(percentage)\n        print  # progress bar doesn't include newline\n\n    # The --filter option allows the user to specify which FITS files, among\n    # all those received as input, must be combined: only those images taken\n    # in the options.filter photometric filter.\n"""

    wcs_needle = """    for img in files:\n        # May raise NoWCSInformationError\n        img.center_wcs()\n"""
    wcs_replacement = """    if not skip_preflight:\n        for img in files:\n            # May raise NoWCSInformationError\n            img.center_wcs()\n"""

    new_data = replace_once(data, preflight_needle, preflight_replacement)
    new_data = replace_once(new_data, wcs_needle, wcs_replacement)
    if new_data != data:
        with open(path, "w") as fh:
            fh.write(new_data)


def main():
    patch_fitsimage()
    patch_mosaic()


if __name__ == "__main__":
    main()
