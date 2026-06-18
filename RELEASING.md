# Releasing

CurseForge builds releases automatically from this repo's git tags (Automatic
Packaging is enabled on the project and linked to this GitHub repository).

## Cutting a release
1. Bump `## Version:` in `AllGasNoBrakes.toc` and add a section to `CHANGELOG.md`.
2. Commit to `main`.
3. Tag and push:

       git tag v1.0.0
       git push origin v1.0.0

CurseForge sees the new tag, packages the repo per `.pkgmeta`, and publishes a file.

## Release type comes from the tag name
- Tag contains `alpha` (e.g. `v1.0.0-alpha1`) -> Alpha file
- Tag contains `beta` (e.g. `v1.0.0-beta1`) -> Beta file
- Anything else (e.g. `v1.0.0`) -> Release file

## What ends up in the package
`.pkgmeta` packages the addon as a single `AllGasNoBrakes/` folder: the `.toc`,
every `*.lua`, the `Media/` folder, `LICENSE`, and `CHANGELOG.md`. Repo-only
files (`tests/`, `docs/`, `images/`, `.github/`, `README.md`) are left out. The
top section of `CHANGELOG.md` is used as the release notes.

## Verify the package before the first real release
Push an alpha tag first and confirm the file on CurseForge unzips to one
`AllGasNoBrakes/` folder with `AllGasNoBrakes.toc` at its top level:

    git tag v1.0.0-alpha1
    git push origin v1.0.0-alpha1

If it looks right, push the real `v1.0.0` tag. The alpha file/tag can be removed
afterward.
