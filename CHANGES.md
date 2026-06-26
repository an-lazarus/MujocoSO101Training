# CHANGES — Phase 1 bring-up (record.sh on WSL2)

A complete, traceable record of everything done to take this repository from "cloned, nothing installed" to "runs `record.sh`, teleoperated, episode saved" on a fresh Windows 11 / WSL2 workstation. Dated 2026-06-25/26.

Every command was run inside **WSL2 Ubuntu 24.04** as user `lazarus`, unless noted. The Python runtime is a `uv` virtual environment at `~/mujoco-sim` (native WSL filesystem, *not* the OneDrive/Windows path, for I/O speed and to avoid cloud-syncing the environment).

---

## 0. Starting state

- Repo cloned to a OneDrive-synced Windows path; contents were only `README.md` (one line), `LICENSE`, `record.sh`, `configs/env_config.json`, `notes/log.md`, `.gitignore`.
- `notes/log.md` documented a *previous, different machine* (conda env `lerobot-hil`). **None of that environment existed** on this machine — WSL Ubuntu was freshly created, with no conda, no Python packages, no compiler.
- Verified available: Ubuntu 24.04, system Python 3.12.3, `venv` module present, **no `pip`**, WSLg active (`/mnt/wslg` present, `DISPLAY=:0`).

## 1. Toolchain — `uv`

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh      # installs to ~/.local/bin, no sudo
```
Rationale: the venv has no `pip`, and `pip` had historically stalled on this project's dependency tree. `uv` is a single self-contained installer/resolver requiring no root.

## 2. Isolated environment

```bash
mkdir -p ~/mujoco-sim && cd ~/mujoco-sim
uv venv --python 3.12                 # creates ~/mujoco-sim/.venv
```

## 3. MuJoCo (smoke test of the renderer)

```bash
uv pip install mujoco                 # 3.10.0 at this point (later resolved to 3.8.1 by lerobot)
```

## 4. LeRobot stack — and the build-dependency failures

```bash
uv pip install "lerobot[hilserl]"
```
This failed **twice** while building `evdev` (pulled in via `lerobot → pynput → evdev`), each time for a missing build-time file on the minimal WSL image:

1. `linux/input.h` missing → no kernel userspace headers.
2. `Python.h` missing → no Python development headers.

Fix (one apt transaction covers both — `build-essential` provides the compiler and `linux-libc-dev`; `python3-dev` provides `Python.h`):
```bash
sudo apt update
sudo apt install -y build-essential python3-dev
uv pip install "lerobot[hilserl]"     # now succeeds
```
> Trap recorded: the `evdev` error suggests `linux-headers-$(uname -r)`. **Do not run this on WSL** — `uname -r` reports the Microsoft WSL kernel, for which no apt package exists. `build-essential` is the correct route.

Verified imports:
```bash
uv run python -c "import lerobot, gym_hil, mujoco, torch; print('ok')"
# lerobot 0.5.1, torch 2.10.0+cu128, gym_hil loaded
```

## 5. `record.sh` — use the sandbox interpreter

The script called bare `python` (system Python, no packages). Changed the interpreter line to the venv's Python by absolute path so no activation is needed:
```diff
- python -m lerobot.rl.gym_manipulator \
+ "$HOME/mujoco-sim/.venv/bin/python" -m lerobot.rl.gym_manipulator \
```

## 6. CRLF line endings

First run failed with `--env.name: command not found` and `$'\r': command not found`. Cause: the script (edited on the Windows side) had CRLF endings, breaking Bash `\` line-continuations. Fix:
```bash
cp "<windows path>/record.sh" ~/record.sh
sed -i 's/\r$//' ~/record.sh          # normalise CRLF → LF
```
The working copy is run from `~/record.sh`.

## 7. Keyboard remap (in `gym_hil`)

File: `~/mujoco-sim/.venv/lib/python3.12/site-packages/gym_hil/wrappers/intervention_utils.py`, class `KeyboardController`. The stock gripper bindings used `Right Ctrl` / `Left Ctrl`; this keyboard has no Right Ctrl. Remapped to character keys and corrected the (previously inaccurate) on-screen help.

- `on_press`: open gripper → `key.char == "o"`; close gripper → `key.char == "p"` (using `hasattr(key, "char")` guards, since letter keys are `KeyCode`, not `keyboard.Key.*`).
- `on_release`: mirror the same two keys (press sets the command `True`, release sets it `False`; press/release must reference the *same* command variable).
- `print(...)` help block updated to match (`o`/`p` gripper; `Esc` = FAILURE, which is what the code actually does).

## 8. Rendering on WSLg — the core problem

Symptom progression (all `SIGSEGV` or framebuffer errors):
- Default GPU path → `MESA: ZINK: failed to choose pdev`, `D3D12: Removing Device`, segfault.
- `MUJOCO_GL=osmesa` → still crashed: the **interactive viewer** ignores `MUJOCO_GL` and `osmesa` provides no window framebuffer → `Default framebuffer is not complete`.

Isolation tests established:
- `mujoco.Renderer` (offscreen) works under `osmesa` *and* under software GLX.
- `mujoco.viewer.launch_passive` (on-screen) works **only** with `MUJOCO_GL=glfw` + `LIBGL_ALWAYS_SOFTWARE=1` + `GALLIUM_DRIVER=llvmpipe` (CPU `llvmpipe` renderer; clean exit 0).
- A combined test (offscreen cameras + viewer together, as `record.sh` does) confirmed both coexist under that combination.

Required system GL libraries:
```bash
sudo apt install -y libgl1 libglfw3 libosmesa6 libglib2.0-0
```
`record.sh` exports (added above the `rm`/python lines):
```bash
export MUJOCO_GL=glfw
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
```

## 9. Video-encoder segfault → H.264

With rendering fixed, the run completed an episode and crashed during **video encoding** (`SVT-AV1 Encoder Lib v3.0.0`, two instances → segfault). A standalone test encoded 128×128 frames successfully with *every* codec including `libsvtav1`, localising the fault to LeRobot's concurrent streaming encode (front + wrist) with the viewer thread alive.

Fix — file `~/mujoco-sim/.venv/lib/python3.12/site-packages/lerobot/rl/gym_manipulator.py`, in the record-mode `LeRobotDataset.create(...)` call (~line 648):
```diff
  dataset = LeRobotDataset.create(
      cfg.dataset.repo_id,
      cfg.env.fps,
      root=cfg.dataset.root,
      use_videos=True,
+     vcodec="h264",
      image_writer_threads=4,
      image_writer_processes=0,
      features=features,
  )
```
`resolve_vcodec("h264")` is valid; libx264 verified working in this PyAV (15.1.0) build.

## 10. Result

`bash ~/record.sh` launches the Panda env, opens an interactive MuJoCo viewer on the Windows desktop, accepts keyboard teleoperation, and saves one episode (H.264 video + parquet) to `~/.cache/huggingface/lerobot/an-lazarus/il_gym_test`. Confirmed working and teleoperated end-to-end.

---

## Fragile edits (will be lost on package upgrade)

These two changes live in installed `site-packages`, **not** in the repository, and any `uv pip install --upgrade` of the respective package overwrites them:

| Change | File (under `~/mujoco-sim/.venv/lib/python3.12/site-packages/`) |
|--------|------------------------------------------------------------------|
| `vcodec="h264"` | `lerobot/rl/gym_manipulator.py` (`LeRobotDataset.create` call) |
| `o`/`p` gripper keys + help text | `gym_hil/wrappers/intervention_utils.py` (`KeyboardController`) |

Future work: replace with a proper fork or runtime configuration override.

## Verified package versions

```
av==15.1.0          gymnasium==1.3.0     pynput==1.8.2
datasets==4.8.5     lerobot==0.5.1       torch==2.10.0
draccus==0.10.0     mujoco==3.8.1        torchcodec==0.10.0
evdev==1.9.3        numpy==2.2.6         torchvision==0.25.0
gym-hil==0.1.14     opencv-python-headless==4.13.0.92   transformers==5.3.0
placo==0.9.16       python==3.12.3
```
