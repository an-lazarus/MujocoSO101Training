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
