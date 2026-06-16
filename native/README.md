# Fairy-Stockfish GDExtension

Compiles Fairy-Stockfish *into* the game as a native library so it runs on
Android and iOS (where spawning `stockfish.exe` as a subprocess is impossible),
as well as on desktop. Exposes a `FairyEngine` node to GDScript with:

- `start()` / `stop()`
- `send_command(text)` — queue a UCI command
- `output_received(line)` — signal, one UCI line at a time, on the main thread

The game uses it through `Scripts/engine_bridge.gd`. There is **no** stockfish.exe
subprocess fallback — the extension is the only engine path on every platform.
If it isn't compiled, `EngineBridge.start()` logs an error and the engine won't
run, so **build the extension before running the game.**

---

## 0. Easiest path: let the cloud build it (no local toolchain)

`.github/workflows/build-extension.yml` compiles all five platforms (Windows,
Linux, macOS, **Android, iOS**) on GitHub's runners — you never install a
compiler, NDK, or Mac.

1. Push this repo to GitHub (one-time): create a repo, then
   `git remote add origin <url>` and `git push -u origin main`.
2. GitHub → **Actions** tab → run **Build GDExtension** (or just push to `main`).
3. When it's green, download the per-platform **Artifacts**, unzip them, and
   drop the files into `addons/fairy_engine/bin/`. Restart Godot — done.

The first run may surface a compile error from the best-guess build flags
(§5); the logs make those easy to fix and re-run. Everything below is only for
building **locally** instead.

---

## 1. Prerequisites for LOCAL builds (none are installed yet on this machine)

| Tool | Why | Get it |
| --- | --- | --- |
| **Python 3** | runs SCons | already installed |
| **SCons** | the build system | `pip install scons` |
| **Git** | clone godot-cpp + engine | https://git-scm.com |
| **C++ compiler** | desktop build | Windows: "Visual Studio Build Tools" w/ C++ workload (MSVC) |
| **Android NDK + SDK** | Android build | via Android Studio; set `ANDROID_HOME` |
| **macOS + Xcode** | iOS build | iOS **cannot** be built from Windows — you need a Mac |

## 2. One-time setup / updating the engine

From the `native/` folder, run the helper script. It clones Fairy-Stockfish and
godot-cpp on first run, and **pulls updates** from GitHub on later runs. Both
folders are gitignored, so it never touches your own git history.

```powershell
# first run, or to pull the latest engine later
.\update_engine.ps1

# pin the engine to a specific release and match your Godot version
.\update_engine.ps1 -Ref fairy_sf_14_largeboards -GodotCppBranch 4.3 -FetchNet
```

- `-Ref` — Fairy-Stockfish branch/tag/commit (default: latest master). Pinning a
  release is safer than always tracking master.
- `-GodotCppBranch` — must match your Godot version (default `4.2`).
- `-FetchNet` — also runs `make net` for the default NNUE net (needs `make`;
  skippable for classical-eval custom variants).

> **After updating to a *newer* engine version**, re-check that the source file
> list / `-Dmain` trick still apply and that the `CPPDEFINES` in `SConstruct`
> still match `Fairy-Stockfish/src/Makefile`, then rebuild and test. Updating is
> pull + rebuild + verify, not a one-click swap.

Prefer to do it by hand instead?

```sh
git clone -b 4.6 https://github.com/godotengine/godot-cpp.git
git clone https://github.com/fairy-stockfish/Fairy-Stockfish.git
cd Fairy-Stockfish/src && make net && cd ../..
```

## 3. Build

```sh
# Windows desktop
scons platform=windows target=template_debug
scons platform=windows target=template_release

# Android (needs NDK; build each ABI you ship)
scons platform=android target=template_release arch=arm64

# iOS (on a Mac)
scons platform=ios target=template_release arch=arm64
```

Outputs land in `addons/fairy_engine/bin/`, matching the paths already listed in
`addons/fairy_engine/fairy_engine.gdextension`. Restart Godot; `FairyEngine`
then appears in `ClassDB` and `EngineBridge` switches to it automatically.

## 4. Godot export settings

- **Include `variants.ini`**: in each export preset's *Resources* tab, add
  `*.ini` to "Filters to export non-resource files" (the engine reads it via a
  globalized `user://` copy made at runtime — see `board_container.gd`).
- You no longer need to ship `Engine/stockfish.exe` in mobile exports.

## 5. Build flags to verify (the untested part)

The wrapper architecture is solid, but Fairy-Stockfish's compile flags vary by
version. Open `Fairy-Stockfish/src/Makefile` and reconcile the `CPPDEFINES` in
`SConstruct`:

- `LARGEBOARDS` / `PRECOMPUTED_MAGICS` — included here to match the common
  "largeboards" binaries (likely what your current `stockfish.exe` is). Remove
  if all your variants fit on an 8x8 board.
- **SIMD** (`USE_AVX2`, `USE_SSE41`, `USE_NEON`, …) — left **off** for portable,
  correct scalar code on ARM. Add per-arch later for desktop search speed.
- **NNUE**: if linking fails on the embedded net symbol, run `make net` (above),
  or disable NNUE for your custom variant.

## How it works (no subprocess, no stdio hacks for the caller)

`main.cpp` is recompiled with `-Dmain=fairy_sf_main`, so we call the engine's
real, version-correct startup + UCI loop on a background thread. Its `std::cin`
and `std::cout` are swapped for in-memory queue buffers, so `send_command()`
feeds the UCI loop and every printed line is forwarded to the `output_received`
signal. Search threads print through the same redirected `std::cout`, so they're
covered too.
