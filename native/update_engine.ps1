<#
.SYNOPSIS
    Clone or update the external dependencies for the Fairy-Stockfish GDExtension.

.DESCRIPTION
    Fetches Fairy-Stockfish and godot-cpp from GitHub into native/. Run it once
    to set up, and again whenever you want to pull updates. Both folders are
    gitignored, so this does not touch your own git history.

    After updating Fairy-Stockfish to a NEWER version, re-check:
      - the source file list / the -Dmain trick still apply (SConstruct)
      - the CPPDEFINES in SConstruct still match Fairy-Stockfish/src/Makefile
    ...then rebuild and test.

.PARAMETER Ref
    Git branch, tag, or commit of Fairy-Stockfish to check out.
    Default: the repo's default branch (latest master).
    Pin to a release for stability, e.g.  -Ref fairy_sf_14_largeboards

.PARAMETER GodotCppBranch
    Branch of godot-cpp to use. MUST match your Godot version. Default: 4.2

.PARAMETER FetchNet
    Also run `make net` to download the default NNUE network (needs `make`).

.EXAMPLE
    .\update_engine.ps1
.EXAMPLE
    .\update_engine.ps1 -Ref fairy_sf_14_largeboards -GodotCppBranch 4.3 -FetchNet
#>
param(
    [string]$Ref = "",
    [string]$GodotCppBranch = "4.6",
    [switch]$FetchNet
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is not installed or not on PATH. Install it from https://git-scm.com first."
    exit 1
}

function Sync-Repo {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Dir,
        [string]$Checkout  # branch/tag/commit, or "" for default branch
    )

    if (Test-Path (Join-Path $Dir ".git")) {
        Write-Host "==> Updating $Name ($Dir)" -ForegroundColor Cyan
        git -C $Dir fetch --all --tags --prune
        if ($Checkout) {
            git -C $Dir checkout $Checkout
            # If it's a branch (not a detached tag/commit), fast-forward it.
            git -C $Dir pull --ff-only 2>$null
        } else {
            git -C $Dir pull --ff-only
        }
    } else {
        Write-Host "==> Cloning $Name -> $Dir" -ForegroundColor Cyan
        if ($Checkout) {
            git clone --branch $Checkout $Url $Dir
        } else {
            git clone $Url $Dir
        }
    }

    $head = git -C $Dir rev-parse --short HEAD
    Write-Host "    $Name is now at $head" -ForegroundColor Green
}

Sync-Repo -Name "Fairy-Stockfish" `
          -Url "https://github.com/fairy-stockfish/Fairy-Stockfish.git" `
          -Dir "Fairy-Stockfish" `
          -Checkout $Ref

Sync-Repo -Name "godot-cpp" `
          -Url "https://github.com/godotengine/godot-cpp.git" `
          -Dir "godot-cpp" `
          -Checkout $GodotCppBranch

if ($FetchNet) {
    Write-Host "==> Fetching default NNUE net (make net)" -ForegroundColor Cyan
    if (Get-Command make -ErrorAction SilentlyContinue) {
        Push-Location "Fairy-Stockfish/src"
        make net
        Pop-Location
    } else {
        Write-Warning "`make` not found; skipping. The engine still builds for classical-eval custom variants."
    }
}

Write-Host "`nDone. Next: rebuild with scons (see README.md)." -ForegroundColor Green
