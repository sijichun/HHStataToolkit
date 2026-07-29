# License and third-party notices

## HHStataToolkit code

Unless a file states otherwise, HHStataToolkit code and documentation are
copyright (C) 2026 Jichun Si (司继春) and released under the GNU General Public
License, version 3 or later. The repository's GPL-3.0 text is currently kept
in the root `COPYING` file; every release artifact must include it alongside
this `LICENSE` notice.

## Files not relicensed by this repository

The following files are supplied by third parties or an official vendor and
retain their own notices and license terms:

- `src/stplugin.h` and `src/stplugin.c`: official StataCorp plugin-interface
  files; copyright StataCorp LP.
- `grf/grf/`: upstream GRF source under GPL-3.0 or later; retain its
  `NOTICE.md` and the root `COPYING` text when distributing this source.
- `grf/grf/core/third_party/Eigen/`: Eigen source, including its own license
  file (MPL-2.0 and notices for included material).
- `grf/grf/core/test/catch.hpp`: Catch2 under its embedded BSL-1.0 notice.
- Other third-party material listed by `grf/grf/NOTICE.md`: retain the stated
  notices and terms.

This file describes repository provenance; it does not replace license notices
embedded in individual third-party files.
