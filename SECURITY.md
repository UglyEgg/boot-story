# Security

Report security issues privately to `uglyegg@entropy.quest`.

The collector invokes a fixed set of local systemd commands without a shell and
under a coherent collection deadline. It writes only an owner-private,
size-bounded, schema-validated mode-0600 history file through a locked atomic
replacement, then emits JSON. Selected-unit
inspection validates the unit name before passing it as a separate argument to
a fixed `systemctl show` query. Boot health uses one incrementally read journal query for
two well-known systemd failure message IDs and ignores events after
`graphical.target` became ready. The query also has hard time, byte, and record
limits. It performs no open-ended journal search and
exposes no unit-management operations.

The application requests no privileges and performs no network access. The
optional login recorder is a delayed systemd user timer plus one-shot service
with networking denied, a private temporary directory, and `NoNewPrivileges`
enabled. Its storage path is supplied explicitly by the unit rather than ambient
environment state.

Release CI accepts only an allow-listed GPG-signed annotated tag whose version
matches the source and whose commit is on `main`. It builds an exact
single-version checksum manifest—including the Debian package—and creates only a
draft GitHub release. Publication is a separate offline-key step that uploads
and reverifies the manifest signature and every remote asset before removing the
draft flag.
