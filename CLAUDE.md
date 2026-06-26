# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Human-in-the-loop imitation-learning pipeline (LeRobot **HIL-SERL**) on **MuJoCo** via **`gym_hil`**. Long-term target: the **SO-101** arm. Current state (Phase 1): the `record.sh` teleoperation/record pipeline runs, validated with the Franka Panda `PandaPickCubeKeyboard-v0` task as a proxy. Scientific framing is in `README.md`; the full bring-up history with diffs and error messages is in `CHANGES.md`; the chronological setup log is in `notes/log.md`.

## The single most important fact

**The runtime is not in this repo, and not on Windows.** This repository sits on a OneDrive/Windows path, but all robot code runs in a **`uv` virtual environment at `~/mujoco-sim`** inside **WSL2 Ubuntu 24.04** (user `lazarus`), Python 3.12.3, CPU-only. Never run robot code with Windows Python. Keep heavy artifacts (venv, datasets, model clones) on the WSL filesystem — never on the OneDrive path (I/O speed + avoid cloud-syncing GBs).

`notes/log.md`'s **Phase 0** section describes a *different, older machine* (a conda env that does not exist here). The live machine is Phase 1.

## Commands

The venv has **no `pip`** (uv-managed). Use `uv pip ...`, or call the interpreter directly as `~/mujoco-sim/.venv/bin/python`.

```bash
# Run the recorder (canonical script; opens viewer, teleop, saves one episode)
bash ~/record.sh

# One-time environment setup (fresh WSL)
curl -LsSf https://astral.sh/uv/install.sh | sh
sudo apt install -y build-essential python3-dev libgl1 libglfw3 libosmesa6 libglib2.0-0
mkdir -p ~/mujoco-sim && cd ~/mujoco-sim && uv venv --python 3.12
uv pip install "lerobot[hilserl]"

# Verify the stack imports
~/mujoco-sim/.venv/bin/python -c "import lerobot, gym_hil, mujoco, torch; print('ok')"

# Syntax-check after editing an installed package file (do this every time)
~/mujoco-sim/.venv/bin/python -c "import gym_hil.wrappers.intervention_utils; print('ok')"

# Exact installed versions
cd ~/mujoco-sim && uv pip freeze
```

There is no build step and no test suite. "Running" means launching `record.sh`. Recorded datasets land in `~/.cache/huggingface/lerobot/an-lazarus/il_gym_test`.

If you copy `record.sh` onto the WSL side from the Windows path, normalise line endings first: `sed -i 's/\r$//' record.sh` (Windows edits introduce CRLF, which breaks Bash continuations: `$'\r': command not found`).

## Architecture (the parts that span multiple files)

Data flow for `record.sh` (entry point: `lerobot.rl.gym_manipulator`, record mode):

1. **Env** — `gym_hil/PandaPickCubeKeyboard-v0` (registered in `gym_hil/__init__.py`). It is the base MuJoCo Panda env wrapped by a *factory* (`gym_hil/wrappers/factory.py`) that layers: keyboard input control + a **`PassiveViewerWrapper`** (`use_viewer: True`) that opens an on-screen `mujoco.viewer`.
2. **Two distinct rendering paths share one process** — and this is the crux of the WSL pain:
   - *Offscreen* camera rendering (`mujoco.Renderer`, the 128×128 `front`/`wrist` images) — obeys `MUJOCO_GL`.
   - *On-screen* viewer (`mujoco.viewer.launch_passive` in `gym_hil/wrappers/viewer_wrapper.py`) — **ignores `MUJOCO_GL`**, always GLFW.
   They must be configured consistently for software rendering (see below), or one path segfaults while the other works.
3. **Teleop** — `gym_hil/wrappers/intervention_utils.py` `KeyboardController` uses `pynput` to read keys globally and emit end-effector deltas; the operational-space controller (`gym_hil/mujoco_gym_env.py` + `controllers/opspace.py`) converts deltas to joint torques.
4. **Recording** — `gym_manipulator` builds a `LeRobotDataset.create(...)` and, per episode, encodes each camera stream to video (PyAV) and writes tabular state to parquet.

CLI flags are parsed by `draccus` (`--env.*`, `--dataset.*`, `--mode`, `--device`); `record.sh` is the source of truth for the exact invocation. `configs/env_config.json` is descriptive only — it is **not** read by `record.sh`.

## Non-negotiable run requirements (WSL2 / WSLg)

Already encoded in `record.sh`; do not remove:

```bash
export MUJOCO_GL=glfw            # NOT osmesa — osmesa breaks the interactive viewer ("framebuffer not complete")
export LIBGL_ALWAYS_SOFTWARE=1   # force llvmpipe; the GPU/Zink/D3D12 path segfaults under WSLg
export GALLIUM_DRIVER=llvmpipe
```

## Edits that live OUTSIDE this repo (fragile — re-apply after any package upgrade)

A `uv pip install --upgrade` of these packages **silently reverts** the fixes and the pipeline starts crashing again. Both are documented with diffs in `CHANGES.md`.

1. **H.264 codec** — `site-packages/lerobot/rl/gym_manipulator.py`, the `LeRobotDataset.create(...)` call needs `vcodec="h264"`. Default `libsvtav1` (SVT-AV1) segfaults during concurrent episode encoding while the viewer thread is alive.
2. **Keyboard remap** — `site-packages/gym_hil/wrappers/intervention_utils.py`, `KeyboardController`: gripper open=`o`, close=`p` (no Right Ctrl on this keyboard); help printout matches.

Teleop keys: Arrows = X-Y · Shift L/R = down/up (Z) · `o`/`p` = open/close gripper · Space = toggle intervention · Enter = success · Esc = failure.

## Debugging philosophy that worked here

Most failures were *environment* failures disguised as application `SIGSEGV`s. When a crash appears, **reproduce the smallest responsible layer in isolation** (a bare `mujoco.Renderer`, a lone GLFW context, a standalone PyAV encode) before re-running the whole pipeline — that is how the rendering and codec faults were localised.
