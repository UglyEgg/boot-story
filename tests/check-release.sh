#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM
assets="$temporary_dir/assets"
mkdir -p -- "$assets"

printf 'source\n' > "$assets/boot-story-0.1.0-source.tar.gz"
printf 'portable\n' > "$assets/boot-story-0.1.0-Linux-x86_64.tar.gz"
printf 'debian\n' > "$assets/boot-story_0.1.0-1_amd64.deb"
printf 'rpm\n' > "$assets/boot-story-0.1.0-1.x86_64.rpm"

"$project_root/scripts/release-manifest.sh" write "$assets" 0.1.0
"$project_root/scripts/release-manifest.sh" verify "$assets" 0.1.0 >/dev/null
"$project_root/scripts/release-manifest.sh" write-complete "$assets" 0.1.0
"$project_root/scripts/release-manifest.sh" verify-complete "$assets" 0.1.0 >/dev/null
test "$(wc -l < "$assets/SHA256SUMS")" -eq 4
rg -Fq 'boot-story_0.1.0-1_amd64.deb' "$assets/SHA256SUMS"

mv -- "$assets/boot-story-0.1.0-1.x86_64.rpm" "$temporary_dir/boot-story.rpm"
if "$project_root/scripts/release-manifest.sh" write-complete "$assets" 0.1.0 >/dev/null 2>&1; then
    printf 'An incomplete release asset set was accepted as complete.\n' >&2
    exit 1
fi
mv -- "$temporary_dir/boot-story.rpm" "$assets/boot-story-0.1.0-1.x86_64.rpm"
"$project_root/scripts/release-manifest.sh" write-complete "$assets" 0.1.0

printf 'tampered\n' >> "$assets/boot-story_0.1.0-1_amd64.deb"
if "$project_root/scripts/release-manifest.sh" verify "$assets" 0.1.0 >/dev/null 2>&1; then
    printf 'A tampered release asset passed verification.\n' >&2
    exit 1
fi

printf 'old\n' > "$assets/boot-story-0.0.9-1.x86_64.rpm"
if "$project_root/scripts/release-manifest.sh" write "$assets" 0.1.0 >/dev/null 2>&1; then
    printf 'A mixed-version release asset set was accepted.\n' >&2
    exit 1
fi
