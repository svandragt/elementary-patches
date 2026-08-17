# `scripts/` implementation invariants

Every `scripts/*.sh` resolves the repo root via `REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` — they live one level down, so the `..` is required. Don't drop it.

quilt on noble does **not** accept `-d <dir>` as a global flag. Always `cd "$SOURCE_DIR"` (in a subshell) before invoking `quilt`, and pass `QUILT_PC=$SOURCE_DIR/.pc QUILT_PATCHES=$SOURCE_DIR/patches --quiltrc "$REPO_DIR/quiltrc"` so config and state are explicit.

Package directories live under `pkgs/` (`PATCHES_DIR="$REPO_DIR/pkgs"`), separate from tooling (`scripts/`, `crash-dashboard/`) and repo config (dotdirectories) at the top level. Discovery loops (`for d in "$PATCHES_DIR"/*/`) don't need to filter by name — everything under `pkgs/` is a package.

## Version bump: `+ep1`

`build.sh` runs `dch --local +ep` before `dpkg-buildpackage`, so a patched build installs as `<archive version>+ep1`.

Without it, the local `.deb` carries the archive's exact version string but different metadata (`Installed-Size`, shlibs-derived `Depends`). apt then holds two `Version` records under one version string, picks the archive's as the candidate, and permanently lists the package as `[upgradable from: <same version>]`. The next `apt full-upgrade` — which `~/bin/sup` runs before `ep rebuild --all` — puts the stock build back over the patched one, `rebuild.sh`'s `installed_hash` sees the files changed, and it rebuilds. Every `sup` run, forever.

`+ep1` sorts above the archive version, so apt leaves it alone; a genuinely newer archive version still sorts above `+ep1` and upgrades normally, which then triggers exactly one rebuild. The bump is guarded by a `grep '+ep1)' debian/changelog` so a repeated `ep build` on the same tree doesn't stack `+ep2`, `+ep3`.

`--install` therefore installs every `.deb` matching the new version (`*_${BUILT_VERSION}_*.deb`), not just `${PACKAGE}_*.deb`: siblings such as `libgala0` carry a `(= version)` dependency on the main binary and must move together. It filters that set to binaries already installed — a source can also produce packages this system never had (`appcenter-casper` needs live-CD-only `casper`, `pantheon-terminal` is a transitional dummy), and `dpkg -i` on those fails the whole install.

## Local, untracked patches

`pkgs/<package>/local/` is an optional second series directory, same shape as `pkgs/<package>/` (its own `series` + numbered `.patch` files), gitignored via `pkgs/*/local/`. It's for patches you want applied on your machine but never committed — WIP, or anything too speculative/personal for the tracked series.

quilt needs one consistent series/patches directory per invocation — it errors ("series file no longer matches the applied patches") if you swap `QUILT_PATCHES` between two directories mid-session, because it checks the current series against `.pc/applied-patches`. So there's no simple two-stage "push tracked, then repoint the symlink and push local" — `scripts/lib.sh`'s `sync_patches_dir` instead rebuilds `$SOURCE_DIR/patches` as one real directory holding a symlink per patch (tracked series first, then `local/series` if present) plus a merged `series` file, and every quilt-consuming script (`apply.sh`, `refresh.sh --rebase`, `rebuild.sh`) pushes that single merged view in one `push -a`/loop. Verified empirically that `quilt refresh` writes a refreshed patch through its symlink in place (not unlink+replace), so edits made via the merged view land back in whichever real directory — tracked or `local/` — a patch's symlink points to.

`new-patch.sh --local` names the new patch with a `local-` prefix (avoids colliding with a tracked patch's filename in the merged view), calls `sync_patches_dir` so quilt sees the full applied history as one consistent series, then `quilt new`. Since `quilt new` writes no real file content until the first refresh, `lib.sh`'s `commit_new_patch` makes sure the patch exists as a real file in its true home (`pkgs/<package>/` or `pkgs/<package>/local/`), appends it to that directory's own `series`, and leaves a symlink in the merged dir so `edit.sh`/`refresh.sh` right after it write straight through. `status.sh` and `rebuild.sh`'s up-to-date hash both fold `local/` in when present.
