# Contributing

Please open an issue before a major behavioral or visual change. Preserve the distinction between critical-path delay and parallel activation time. Collection must remain local and unprivileged. Background recording must remain one-shot rather than resident unless measurements justify a change.

Run `make check` before submitting changes. Every QML or JavaScript runtime file
must be added to `BOOT_STORY_QML_FILES`; the source checks reject resource-list
drift. New collector probes must preserve the overall deadline and expose an
explicit availability result rather than silently converting missing evidence
to an empty result.

Fedora 44 and Ubuntu 26.04 LTS are the reference build environments. Pull
requests must keep the portable checks, the Fedora RPM build, and the Ubuntu
Debian-package build green. Package and release changes should be tested with the
matching `make package-rpm`, `make package-deb`, or `make release` target.
