# Phase 0 Setup Log

| Date | Step | What happened | Time spent | Fixes applied |
|------|------|---------------|------------|---------------|
| 2026-06-20 | Repo clone | Cloned an-lazarus/MujocoSO101Training into ~/projects/MujocoSO101Training | ~1 min | None |
| 2026-06-20 | Dir structure | Created configs/, notes/, .gitignore | <1 min | None |
| 2026-06-20 | Python env | Conda env `lerobot-hil` at ~/miniforge3/envs/lerobot-hil/, Python 3.12.13. NOTE: gym_hil README says 3.10 but lerobot main now requires >=3.12 — switched from venv+3.10 to conda+3.12 | 5 min | Switched from venv+3.10 to conda+3.12 after pip failed with "requires Python >=3.12" |
| 2026-06-20 | lerobot clone | Cloned huggingface/lerobot (--depth 1 shallow) into lerobot/. Full clone failed with WSL2 git pack temp-file error (exit 128); shallow clone succeeded | 8 min | Used `git clone --depth 1` to work around WSL2 large-repo git pack bug |
| 2026-06-20 | pip install | Switched to `uv pip install -e "lerobot/[hilserl]"` after pip (26.1.2) stalled 10+ min in dependency resolution without installing anything. uv resolved and downloaded ~8GB of packages (PyTorch CUDA + NVIDIA CUDA libs + gym_hil etc.). WSL2 ext4 write speed was ~3-8 MB/s for large shared libs. Total install time ~33 min | ~33 min | Killed pip, installed uv via pip, used `conda run -n lerobot-hil uv pip install` |
| 2026-06-20 | Verify imports | `import gym_hil` and `import mujoco` both succeed | <1 min | None |
| 2026-06-20 | Versions | gym-hil: 0.1.14, mujoco: 3.8.1, lerobot: 0.5.2, torch: 2.11.0+cu128, transformers: 5.5.4, datasets: 4.8.5, grpcio: 1.81.1, placo: 0.9.15, Python: 3.12.13 | — | — |
| 2026-06-20 | Config | Created configs/env_config.json with PandaPickCubeKeyboard-v0, fps=10, cpu device, push_to_hub=false | <1 min | None |

## Environment details

- **Conda env name:** `lerobot-hil`
- **Conda env path:** `~/miniforge3/envs/lerobot-hil/`
- **Activate with:** `conda activate lerobot-hil`
- **lerobot clone:** `~/projects/MujocoSO101Training/lerobot/` (shallow, upstream read-only)
- **Platform:** WSL2 (Ubuntu on Windows), Linux x86_64

## Key packages installed (hilserl extras)

| Package | Version |
|---------|---------|
| gym-hil | 0.1.14 |
| mujoco | 3.8.1 |
| lerobot | 0.5.2 |
| torch | 2.11.0+cu128 |
| transformers | 5.5.4 |
| datasets | 4.8.5 |
| grpcio | 1.81.1 |
| placo | 0.9.15 |

## Notes on known friction points

1. **Python 3.10 → 3.12**: gym_hil README says 3.10, but lerobot main branch now requires >=3.12. Always use 3.12+.
2. **git clone on WSL2**: Full lerobot clone fails with pack indexing error. Always use `--depth 1` for large repos on WSL2.
3. **pip vs uv**: pip 26 stalls in dependency resolution for lerobot's complex dep tree (10+ min, zero packages installed). Use `uv` for installs in this project.
4. **CUDA libs on CPU setup**: PyTorch for Linux downloads CUDA-enabled version (~8GB total including NVIDIA CUDA stubs) even if `device: cpu`. Accept this — it's the default torch on Linux.
5. **WSL2 write speed**: Large shared library extraction (.so files) writes at 3-8 MB/s — expect 30-40 min for fresh installs.

---

# Phase 1 Setup Log — fresh WSL2 machine (record.sh end-to-end)

> NOTE: The Phase 0 log above is from a *different, older machine* (conda env `lerobot-hil`).
> This Phase 1 was done on a fresh **WSL2 Ubuntu 24.04** install where nothing was preinstalled.
> Runtime env: `uv` venv at `~/mujoco-sim`, Python 3.12.3. Full traceable detail in `CHANGES.md`.

| Date | Step | What happened | Fixes applied |
|------|------|---------------|---------------|
| 2026-06-25 | Assess | Cloned repo had no environment; WSL Ubuntu 24.04 fresh, system Python 3.12.3, no pip, no conda. WSLg active (DISPLAY=:0) | Built from scratch with `uv` |
| 2026-06-25 | uv | Installed `uv` via official script (no sudo) | — |
| 2026-06-25 | venv | `uv venv --python 3.12` at `~/mujoco-sim` | — |
| 2026-06-25 | mujoco | `uv pip install mujoco` (3.10.0; later resolved to 3.8.1 by lerobot) | — |
| 2026-06-25 | lerobot | `uv pip install "lerobot[hilserl]"` failed building `evdev` twice (missing `linux/input.h`, then `Python.h`) | `sudo apt install build-essential python3-dev` |
| 2026-06-25 | record.sh | Bare `python` → venv interpreter by absolute path | Edited interpreter line |
| 2026-06-25 | CRLF | Script had CRLF (`$'\r'`), broke line-continuations | `sed -i 's/\r$//'`; run `~/record.sh` |
| 2026-06-25 | keymap | No Right Ctrl on keyboard | Remapped gripper to `o`/`p` in gym_hil `intervention_utils.py` |
| 2026-06-26 | render | GPU/Zink/D3D12 segfault; `osmesa` broke the viewer ("framebuffer not complete") | `MUJOCO_GL=glfw` + `LIBGL_ALWAYS_SOFTWARE=1` + `GALLIUM_DRIVER=llvmpipe`; `apt install libgl1 libglfw3 libosmesa6 libglib2.0-0` |
| 2026-06-26 | encode | SVT-AV1 (libsvtav1) segfault during concurrent episode encode | `vcodec="h264"` in lerobot `gym_manipulator.py` `LeRobotDataset.create(...)` |
| 2026-06-26 | ✅ run | `record.sh` launches viewer, teleoperated, episode saved to `~/.cache/huggingface/lerobot/an-lazarus/il_gym_test` | — |

## Phase 1 environment details

- **Runtime:** `uv` venv `~/mujoco-sim/.venv`, Python 3.12.3, WSL2 Ubuntu 24.04, CPU-only.
- **Run command:** `bash ~/record.sh` (canonical copy committed in repo).
- **Key versions:** lerobot 0.5.1, gym-hil 0.1.14, mujoco 3.8.1, gymnasium 1.3.0, torch 2.10.0+cu128, PyAV 15.1.0, numpy 2.2.6.

## Phase 1 known friction points

1. **`build-essential` + `python3-dev`** are mandatory on a fresh WSL (evdev compiles from source). The error's suggested `linux-headers-$(uname -r)` does NOT work on WSL.
2. **Software GL is mandatory under WSLg.** Use `glfw` + `llvmpipe`; never `osmesa` when a viewer window is wanted.
3. **Default video codec crashes.** Force `h264` instead of `libsvtav1`.
4. **Two fixes live in installed packages** (codec, keymap) and are lost on `pip --upgrade` — see `CHANGES.md` §"Fragile edits".
