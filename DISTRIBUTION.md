# Distribution

## Steam Frame releases (this fork)

Releases here are **source only**: a `frame-<name>` tag (`frame-beta-2`, ...) and GitHub's source
archives for it. The game is always built from the player's own clean PAL `RMCP01` disc, so no
release, issue or download may carry a disc image, extracted game files, translated game code or a
built game executable, and nobody may share one built from their disc.

To publish one, add its notes as `docs/releases/<tag>.md`, then run **Actions → Steam Frame
release → Run workflow** with the tag (`.github/workflows/frame-release.yml`). The workflow creates
the tag on the commit it runs on and publishes a pre-release with those notes; pushing a `frame-*`
tag runs it as well. The installer (`Launcher/steam-frame-install.sh`) builds the newest release by
default, so publish only what has been built and installed on a Frame.

## Windows (upstream)

The rest of this file is upstream's process for its Windows installer and is kept for reference.
This fork does not publish Windows builds; use upstream's releases for those.

Distribute only `WiiCompiled-Setup.exe` and its checksum from
[iChris4/Wiicompiled_VR](https://github.com/iChris4/Wiicompiled_VR/releases), and
`WheelWizardVRWindows.exe` from [iChris4/WheelWizard_VR](https://github.com/iChris4/WheelWizard_VR/releases).
Installation requires the user's clean PAL RMCP01 image. Neither release includes a disc image,
extracted game assets, translated game code, compiled game executables, saves, or ghosts.

The backend version is declared once in `Launcher/Directory.Build.props`. Before choosing a new
patch version, compare source pins, published releases, and tags in the VR fork. Tags use `vX.Y.Z`.
The Windows workflow checks the tag, executable, and payload contract and runs the translator,
synthetic runtime, setup self-tests, pinned dependency preparation, payload boundary audit, and
native dependency audit. OpenXR uses the pinned SDK sources and static loader; license notices
are included in the installer.

Build from the repository root on Windows:

```powershell
./Launcher/Build-Installer.ps1 -OutputDirectory Launcher/dist-vr
./Launcher/Verify-Release.ps1 -Tag v0.2.45 -SetupPath (Resolve-Path Launcher/dist-vr/WiiCompiled-Setup.exe)
./Launcher/dist-vr/WiiCompiled-Setup.exe --self-test
./Launcher/Test-Recompilation.ps1 -StageDirectory build/vr-synthetic-validation
dotnet test translator/Translator.sln -c Release
```

`--version` still prints a plain version. `--info-json` additionally reports `productId` as
`wiicompiled-openxr-vr`, `version`, `openxrD3D12: true`, and `questBuild: true` when the setup
supports `--build-quest` (see `docs/quest-port.md`). From 0.2.39 every release declares it, and
`Verify-Release.ps1` refuses one whose payload lacks the `BuildWorkspace/android` scripts that
build runs, so a release that claims Quest support can always deliver it. WheelWizard offers
Build for Quest only once the installed setup reports `questBuild`, and asks the player to update
otherwise. VR refuses installation, repair,
launch, or uninstall of a normal or unidentified installation. Nonportable VR installations use
`WiiCompiledOpenXRVR` application data and a distinct uninstall registration and shortcut.

WheelWizard VR keeps its own `config-vr.json`, importing `config.json` only on first use. Its
`Recomp` and `RecompVR` roots own their setup caches, toolkits, build workspaces, extracted assets,
binaries, configuration, runtime caches, and logs. Only the normal NAND and canonical Retro Rewind
content are shared. Controller mappings are seeded from normal once when available. Uninstall
removes the selected `Install` and `Cache` directories and retains `UserData` and imported NAND.

A shared file lease covers supported launcher operations through mod preparation, reconciliation,
and game exit, including shared-data edits and uninstall. Installation locks and running processes
are also checked. Arbitrary direct launches of older game binaries do not participate in this
guarantee. Close games before using another launcher or editing shared data externally.

Retro Rewind remains supplied by WheelWizard's existing distribution service. The chosen backend
builds both products with its own toolkit. Asset-only changes do not require compilation; changes
to Code.pul, translation inputs, or Retro-WFC payloads are reconciled before Retro Rewind launches.
The inactive backend is checked on its next selection. Base launches use `--launch-base`.

WheelWizard VR prepares Retro Rewind updates and reinstalls in a sibling staging tree. Only a
completed update is published. The journal supports recovery after interrupted directory swaps;
existing ghosts, saves, XML save directories, and local patches survive package replacement.

Before publishing, validate both artifacts and install beside an existing normal installation.
Check all four backend/game combinations, saves and Miis across switches and reinstall/uninstall,
Retro Rewind ghosts and content updates, cancellation, interrupted downloads, rollback, and
overlapping processes. Headset acceptance also requires menus, races, headset absence, and runtime
loss for both VR products. Record unperformed checks explicitly. Publish the backend first; the
launcher release workflow requires a published VR backend before releasing the launcher.
