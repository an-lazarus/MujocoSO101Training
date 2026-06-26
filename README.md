# MujocoSO101Training

Bring-up of a human-in-the-loop imitation-learning pipeline for low-cost robot manipulators, built on **MuJoCo**, **HuggingFace LeRobot**, and **`gym_hil`**. The longer-term target is the **SO-101** arm; this repository currently establishes and validates the simulation, teleoperation, and data-recording toolchain using the Franka Panda *pick-cube* task as a stand-in.

---

## 1. Motivation

Modern manipulation policies are increasingly learned from demonstration rather than hand-engineered. The **HIL-SERL** family of methods (Human-In-the-Loop Sample-Efficient Robot Learning) combines (i) human teleoperated demonstrations and (ii) on-line human interventions to bootstrap and correct a learned policy. LeRobot provides an open implementation of this workflow, and `gym_hil` supplies MuJoCo-based environments instrumented for human intervention.

The practical question this repository addresses first is deliberately narrow and infrastructural:

> *Can we stand up the full record → dataset pipeline, with a live interactive viewer, on commodity hardware (a Windows workstation running WSL2, CPU-only), and capture a human demonstration episode end-to-end?*

Establishing this reproducibly is a prerequisite for the scientific work that follows (policy training, intervention-based fine-tuning, and transfer to the physical SO-101).

## 2. Current scope (Phase 0 → Phase 1)

| Phase | Goal | Status |
|-------|------|--------|
| **0** | Install the LeRobot + `gym_hil` + MuJoCo stack; verify imports | ✅ complete |
| **1** | Run `record.sh`: launch the Panda keyboard-teleop env, render an interactive viewer, teleoperate, and persist one episode to a LeRobot dataset | ✅ complete (CPU, WSL2) |
| 2 | Train / evaluate a policy from recorded demonstrations | planned |
| 3 | Port environment and pipeline to the physical **SO-101** arm | planned |

The Panda *pick-cube* task (`PandaPickCubeKeyboard-v0`) is used as a representative manipulation proxy. It shares the operational-space control and gripper action interface that the SO-101 work will need, so the pipeline validated here transfers conceptually.

## 3. Pipeline overview

```
        ┌──────────────┐   operational-space   ┌───────────────┐
keyboard│ KeyboardCtrl │  ───────────────────▶ │  gym_hil env  │
(pynput)│ (intervention│      action (Δx,Δy,Δz,│ (MuJoCo Panda)│
        │   wrapper)   │       grip)           │  + 2 cameras  │
        └──────────────┘                       └──────┬────────┘
                                                       │ obs: agent_pos + pixels(front,wrist)
                                                       ▼
                                      ┌───────────────────────────────┐
                                      │ lerobot.rl.gym_manipulator     │
                                      │  record mode → LeRobotDataset  │
                                      │  (H.264 video + parquet)       │
                                      └───────────────────────────────┘
```

- **Environment:** `gym_hil` Franka Panda in MuJoCo (`gym_hil/PandaPickCubeKeyboard-v0`), 128×128 `front` and `wrist` RGB cameras, operational-space controller, parallel-jaw gripper.
- **Teleoperation:** keyboard via `pynput`; a passive `mujoco.viewer` window provides live 3-D feedback.
- **Recording:** `lerobot.rl.gym_manipulator --mode record` writes a `LeRobotDataset` (per-episode camera videos + tabular state) to the local HuggingFace cache.

## 4. Reproducing the working setup

Validated configuration (see [`CHANGES.md`](CHANGES.md) for the full derivation and [`notes/log.md`](notes/log.md) for the chronological log):

| Component | Version |
|-----------|---------|
| OS | Windows 11 + **WSL2 Ubuntu 24.04** (WSLg) |
| Python | 3.12.3 (in a `uv` virtual env at `~/mujoco-sim`) |
| lerobot | 0.5.1 |
| gym-hil | 0.1.14 |
| mujoco | 3.8.1 |
| gymnasium | 1.3.0 |
| torch | 2.10.0 (+cu128 build, run on CPU) |
| PyAV | 15.1.0 |
| numpy | 2.2.6 |

Setup, in brief (full commands in [`CHANGES.md`](CHANGES.md)):

```bash
# 1. tooling
curl -LsSf https://astral.sh/uv/install.sh | sh
sudo apt install -y build-essential python3-dev \
                    libgl1 libglfw3 libosmesa6 libglib2.0-0

# 2. environment
mkdir -p ~/mujoco-sim && cd ~/mujoco-sim
uv venv --python 3.12
uv pip install "lerobot[hilserl]"

# 3. run (see record.sh for the full invocation)
bash ~/record.sh
```

### Teleoperation controls

| Key | Action |
|-----|--------|
| Arrow keys | Move end-effector in X–Y |
| Left / Right Shift | Move down / up (Z) |
| `o` / `p` | Open / close gripper |
| Space | Toggle intervention (take control) |
| Enter | End episode → SUCCESS |
| Esc | End episode → FAILURE |

## 5. Engineering challenges (and why they are non-trivial on WSL2)

This is the part most relevant to anyone attempting to reproduce robot-learning tooling on a Windows/WSL2 workstation rather than a native Linux GPU box. Each issue below produced an opaque failure (a `SIGSEGV`, a build error, or a malformed-argument error) that required isolating the responsible layer before it could be fixed.

1. **Native build dependencies on a minimal WSL image.** `pynput` → `evdev` compiles a C extension at install time. A fresh Ubuntu-on-WSL lacks both a compiler and the kernel/Python headers, producing two successive build failures. The package's own suggestion (`linux-headers-$(uname -r)`) is *wrong* on WSL, where `uname -r` reports the Microsoft kernel and no matching apt package exists. Resolution: `build-essential` (provides `linux-libc-dev`) + `python3-dev`.

2. **OpenGL under WSLg.** MuJoCo's default GPU rendering path (Mesa → Zink → Direct3D12) is unstable under WSLg and segfaults when a *visible* window framebuffer is requested. The fix is to force CPU software rendering (`llvmpipe`) for the on-screen viewer (`LIBGL_ALWAYS_SOFTWARE=1`, `GALLIUM_DRIVER=llvmpipe`) while keeping `MUJOCO_GL=glfw`. A subtlety worth recording: setting `MUJOCO_GL=osmesa` (the usual headless recommendation) *breaks the interactive viewer* with `Default framebuffer is not complete`, because OSMesa is offscreen-only and provides no window framebuffer. The on-screen and off-screen rendering paths must therefore be configured independently and consistently.

3. **Video-encoder segmentation fault.** LeRobot encodes each episode's camera streams to video. Its default codec, `libsvtav1` (SVT-AV1 v3.0.0), segfaults when two encoder instances are constructed concurrently while the viewer thread is live. The same codec encodes correctly in isolation, which localised the fault to concurrent use. Resolution: pass `vcodec="h264"` (libx264) to `LeRobotDataset.create(...)`.

4. **Cross-filesystem and line-ending hazards.** The repository lives on a OneDrive-synced Windows path; the runtime lives on the native WSL filesystem for I/O performance and to avoid cloud-syncing a multi-GB environment. Shell scripts edited on the Windows side acquire CRLF line endings, which break Bash line-continuations (`$'\r': command not found`); they must be normalised (`sed -i 's/\r$//'`).

A short, characteristically WSL-specific lesson: most failures were *environment* failures masquerading as application crashes. The debugging method that worked was to reproduce each suspected layer in isolation (a minimal `mujoco.Renderer`, a bare GLFW context, a standalone codec encode) rather than re-running the full pipeline.

## 6. Repository structure

```
MujocoSO101Training/
├── README.md            – this document
├── CLAUDE.md            – machine-readable project/setup notes for AI coding agents
├── CHANGES.md           – full, traceable changelog of the bring-up
├── record.sh            – the validated record-mode launch script
├── configs/
│   └── env_config.json  – environment / dataset parameters
└── notes/
    └── log.md           – chronological setup log (Phase 0 + Phase 1)
```

> **Note on modified dependencies.** Two fixes (the H.264 codec selection and the keyboard remapping) currently live as edits inside the *installed* `lerobot` and `gym_hil` packages, not in this repository. They will be overwritten by any package upgrade. See [`CHANGES.md`](CHANGES.md) §"Fragile edits" for the exact locations; productionising these as a fork or runtime override is tracked as future work.

## 7. Roadmap

- Lift `max_episode_steps` and record a small demonstration set for the pick-cube task.
- Replace the in-place package edits with a maintainable mechanism (config override or thin fork).
- Train a baseline policy from the recorded dataset and evaluate in-sim.
- Port the environment, controller, and recording pipeline to the physical SO-101 arm.

## 8. Acknowledgements

Built on [HuggingFace LeRobot](https://github.com/huggingface/lerobot), [`gym_hil`](https://github.com/HuggingFace/gym-hil), and [MuJoCo](https://mujoco.org/).
