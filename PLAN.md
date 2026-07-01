# 3D Perception → SO-101 Stacking: Project Plan

Personal research/portfolio project layered on top of this repo's Phase 1 pipeline. Builds a from-scratch 3D perception stack (PointNet/PointNet++) and drives a simulated SO-101 through block stacking, independently testing the same 3D-vs-RGB hypothesis RISE (IROS 2024) demonstrated on its own "Stack Blocks" task. This plan supersedes the informal version discussed earlier — it has been adversarially reviewed (one agent arguing for it, one against, each backed by sources) and the claims independently re-verified. See [Verified findings](#verified-findings) and [Risk register](#risk-register) at the bottom for what changed and why.

## Interview line (verified/honest version)

> "I built a 3D perception pipeline — point cloud segmentation and pose estimation from an RGBD camera — from scratch, and used it to drive a simulated SO-101 through block stacking. RISE (IROS 2024) showed 3D-aware perception beats RGB-only on this exact task on real hardware; I designed and ran my own version of that comparison in a different setting — simulation, a low-cost arm, a perception model I built and understand end-to-end — to test whether the same finding holds."

Do not say "reproduced RISE's result" — different robot (SO-101 vs. Flexiv Rizon 4), different setting (sim vs. real), different perception architecture. Same task name, everything else differs. Say "independently tested the same hypothesis."

## GPU vs. CPU path — decide in Week 1, not later

You have a **12GB RTX PRO 3000 Blackwell mobile GPU** available, but WSL2 CUDA passthrough for this specific architecture is bleeding-edge (Blackwell is compute capability `sm_120`; official stable PyTorch only gained real `sm_120` kernels very recently, and WSL2's own Blackwell driver fixes only landed in a late-2025 pre-release). It may just work — or it may silently fall back / error. Verify before trusting the schedule to it.

**Day 1 GPU check** (run inside the WSL2 venv):
```bash
python -c "import torch; x=torch.randn(1000,1000).cuda(); print(torch.cuda.get_device_capability(), (x@x).sum().item())"
```
- If this runs clean → **GPU path**.
- If it throws `CUDA error: no kernel image is available for execution on the device` → try a `cu128`/`cu129` **nightly** torch build once; if still broken, don't burn more than an hour on it — fall back to the **CPU path** and revisit later.

| | GPU path (if Day 1 check passes) | CPU path (fallback) |
|---|---|---|
| Stage 1 dataset/model size | Full ModelNet/ShapeNet subset, standard point counts | Scoped down: ~2-4 classes, downsampled to ~1k-2k points |
| Stage 1 training time | Minutes-low hours per run | Hours, possibly overnight — budget fewer iterations |
| Stage 3 (ACT/SmolVLA) | Feasible locally, in-window stretch goal | Needs a cloud GPU — budget ~$20-50 for a short Colab Pro / RunPod / Lambda rental, or defer to winter |
| MuJoCo on-screen viewer | **Unaffected either way** — the existing `MUJOCO_GL=glfw` + `LIBGL_ALWAYS_SOFTWARE=1` + `GALLIUM_DRIVER=llvmpipe` software-rendering workaround stays regardless of GPU, per `CLAUDE.md`. GPU rendering paths are known-unstable under WSLg independent of which GPU is installed. | same |

Whichever path you land on, write the outcome (and any fix needed) into `CHANGES.md` — this repo already has a pattern of environment fixes silently reverting on upgrade; document it the same way as the H.264 codec and keyboard-remap fixes.

## Timeline

| Weeks | Dates | Stage | Deliverable |
|---|---|---|---|
| 1 | Jun 29 – Jul 5 | Stage 0 — Setup | Hardware ordered, env set up, GPU/CPU path decided |
| 2-3 | Jul 6 – Jul 19 | Stage 1a — PointNet classification | Classifier trained on public data, from scratch, defendable cold |
| 4 | Jul 20 – Jul 26 | Stage 1b — PointNet++ segmentation | Segments + localizes blocks on public/synthetic data |
| 5 | Jul 27 – Aug 2 | Stage 1c — Real hardware validation | Model run on own RGBD captures; positioning write-up. **Go/No-Go checkpoint.** |
| 6-7 | Aug 3 – Aug 16 | Stage 2a — SO-101 sim + IK | MuJoCo SO-101 scene (official MJCF) + `mink` Jacobian IK validated |
| 8 | Aug 17 – Aug 23 | Stage 2b — Closed loop | Perceive → IK → place, 2-4 block stack in sim. Ships before Aug 24 outreach deadline. |
| Sept+ | — | Polish | Write-up, demo video, applications open |
| Winter (stretch) | — | Stage 3 | ACT/SmolVLA fine-tune, 3D-vs-RGB stack-height ablation |

**Minimum viable outcome:** Stage 1 alone (Weeks 1-5) is a complete, real, gap-closing deliverable on its own — not a failure state if Stage 2 slips.

**Go/No-Go checkpoint (end of Week 5, tied to hardware, not calendar):** if the SO-101 hasn't shipped by then, commit to the Stage-1-only deliverable for outreach. Do not compress Stage 2/2b to compensate — that's exactly the kind of schedule pressure that caused the documented 3-week (not 2-week) real-hardware SO-101 bring-up referenced in the risk register below.

---

## Task breakdown

### Stage 0 — Setup (Week 1)

- [ ] Order SO-101 (assembled) from **two channels simultaneously** — primary retailers (WowRobo, PartaBot, RCDrone) are showing sold-out on assembled units; back up with eBay third-party or Hiwonder stock
- [ ] Order RGBD camera (RealSense D405 recommended — 7-50cm ideal range matches desk-scale blocks)
- [ ] Confirm WSL2 venv at `~/mujoco-sim` still imports cleanly: `~/mujoco-sim/.venv/bin/python -c "import lerobot, gym_hil, mujoco, torch; print('ok')"`
- [ ] Run the **Day 1 GPU check** above; record the result and pick GPU or CPU path
- [ ] Install point-cloud deps (`open3d` or similar for point cloud I/O/visualization)
- [ ] Pull `yanx27/Pointnet_Pointnet2_pytorch` as a reference implementation to study (not copy) — read through the T-Net, set abstraction, and FPS/ball-query code before writing your own
- [ ] Pick the public dataset for Stage 1a (ModelNet40 subset, or synthetic primitives if you want block-like shapes specifically) — scope per the GPU/CPU table above

### Stage 1a — PointNet classification (Weeks 2-3)

- [ ] Implement point cloud input pipeline: load, normalize, random sample/pad to fixed N points
- [ ] Implement input/feature T-Net (learned alignment transform) from scratch
- [ ] Implement shared MLP layers (per-point feature extraction via 1D conv / linear+ReLU)
- [ ] Implement symmetric max-pooling for permutation invariance
- [ ] Implement classification head (MLP → softmax over classes)
- [ ] Train on chosen dataset/class subset; log accuracy
- [ ] Write your own short notes explaining *why* T-Net and max-pooling exist (permutation invariance, alignment) — this is the part you need to defend cold in an interview
- [ ] Sanity check: confusion matrix, a few misclassified examples inspected manually

### Stage 1b — PointNet++ segmentation extension (Week 4)

- [ ] Implement Farthest Point Sampling (FPS), naive version first
- [ ] Implement ball query grouping around FPS-selected centroids
- [ ] Build one or two Set Abstraction (SA) layers using FPS + ball query + shared MLP
- [ ] Build Feature Propagation (upsampling/interpolation) layers for per-point segmentation output
- [ ] Add segmentation head: per-point class label (block vs. background, or per-block instance if attempting multi-block)
- [ ] Train/validate on synthetic or public segmentation data
- [ ] (Only if CPU path and it's too slow) profile FPS/ball query and optimize the naive loop-based version

### Stage 1c — Real hardware validation (Week 5)

- [ ] Set up RealSense SDK / `pyrealsense2` in WSL2 (note: needs USB passthrough via `usbipd-win` from the Windows side — a new integration point not yet exercised in this repo, budget time for first-run friction)
- [ ] Capture point clouds of 2-4 real colored blocks on your desk under a few lighting conditions
- [ ] Run the trained Stage 1a/1b model on real captures; qualitatively check segmentation/pose quality
- [ ] Iterate on obvious domain-gap fixes (table-plane cropping, color/depth normalization, point density mismatch vs. training data)
- [ ] Draft the "honest positioning" section of the write-up: state clearly what RISE evaluated (real Flexiv Rizon 4, 6 real-world tasks including Stack Blocks) vs. what you're doing (simulated SO-101, own model) — this is the "in progress with results" deliverable for PI outreach
- [ ] **Go/No-Go checkpoint**: has SO-101 hardware shipped/arrived? If not, formally scope down to Stage-1-only for outreach purposes and keep Stage 2 as a background task

### Stage 2a — SO-101 in MuJoCo + IK (Weeks 6-7)

- [ ] Pull the official SO-101 MJCF/URDF from `TheRobotStudio/SO-ARM100` (`Simulation/SO101`) — do **not** try to add SO-101 support inside `gym_hil` (it only supports Franka Panda natively; this is a hard framework limit, not a config option)
- [ ] Load the MJCF standalone in MuJoCo (bypassing `gym_hil` entirely for this stage), sanity-check joint ranges/actuators against the two provided calibrations (`so101_new_calib.xml` / `so101_old_calib.xml`)
- [ ] Install `mink` (MuJoCo-based differential IK library) as your IK solver rather than deriving Jacobian IK from scratch
- [ ] Script a test harness: command the end-effector to a sequence of scripted target poses, verify convergence and joint-limit behavior
- [ ] Add block objects + table plane to the scene; this is where most of the real friction will be — tune contact/friction/solver params for stable stacking, not kinematics
- [ ] Decide and document how perception feeds sim: either (a) render synthetic depth/point clouds from the MuJoCo scene and run your trained model on those, or (b) read ground-truth block poses from MuJoCo state as a stand-in and reserve the real-camera pipeline for the Stage 1c validation only — pick one explicitly, don't leave it ambiguous going into Stage 2b

### Stage 2b — Closed loop stacking (Week 8)

- [ ] Wire: perception output (pose estimate) → IK target → scripted pick/place motion
- [ ] Implement stacking order logic for 2-4 blocks (e.g., largest-to-smallest, matching RISE's Stack Blocks task definition)
- [ ] Debug contact stability during stacking (blocks toppling, gripper slip) — budget slack here by trimming Stage 1a iteration count if needed, not by cutting this step short
- [ ] Record episode videos and any quantitative metric (stack height achieved, success rate over N trials)
- [ ] Write up the closed-loop result for the outreach deliverable

### Stage 3 — 3D-vs-RGB ablation (stretch, winter)

- [ ] Confirm GPU/CPU path decision still holds (re-run the Day 1 check if using a different machine/environment by then)
- [ ] If CPU path: line up a cloud GPU (Colab, RunPod, or Lambda; budget ~$20-50) before starting — don't discover the GPU requirement mid-training
- [ ] Collect demonstration episodes (reuse `record.sh`-style teleop, or scripted demos in the closed-loop sim)
- [ ] Train baseline policy: RGB-only input (ACT or SmolVLA)
- [ ] Train comparison policy: RGB + 3D pose/point-cloud input
- [ ] Evaluate both on stack-height / success-rate metric, same protocol for both
- [ ] Write up the comparison, citing RISE/ACT/Diffusion Policy numbers as *context* (what the literature found on real hardware) rather than a number you're claiming to match

---

## Verified findings

Both an attacking and a defending review pass were run against this plan, each required to cite real sources; claims were then independently re-checked. Net effect on the plan:

- **Corrected:** RISE's benchmark *does* include a "Stack Blocks" task (one of 6 real-world tasks: Collect Cups, Collect Pens, Pour Balls, Push Block, Push Ball, Stack Blocks) — confirmed directly from RISE's project page/GitHub. An earlier review pass claimed otherwise; that was wrong. This doesn't make the sim/SO-101 version a "reproduction," but it does mean the task choice is directly and correctly tied to RISE's own evaluation, not a generic benchmark borrowed from elsewhere.
- **Confirmed:** `gym_hil` supports only Franka Panda — no SO-101 environment exists in it. Stage 2 must bypass it, per the task breakdown above.
- **New finding (neither review pass caught this):** an official SO-101 MJCF/URDF already exists, maintained by the arm's manufacturer (`TheRobotStudio/SO-ARM100`), which substantially de-risks Stage 2 — no kinematic model needs to be built from scratch.
- **Confirmed but weaker than argued:** a documented real-hardware SO-101 HIL-SERL bring-up took ~3 weeks for a single-cube grasp task, citing missing URDF-based real-time IK as the blocker. That blocker was specific to real motors + a real-time IK library's encoder-drift bug — not to an absent simulation model. Stage 2 here is scripted IK in pure simulation, a materially easier problem, so the 2-week budget is more plausible than that precedent suggests, though MuJoCo contact-physics tuning for stacking remains a real, separate source of friction.
- **Confirmed:** SO-101 assembled-unit stock is genuinely tight at major retailers right now — hence the dual-order recommendation in Stage 0.
- **Resolved by your hardware:** the original GPU-gap concern for Stage 3 is moot given the RTX PRO 3000 Blackwell — the only open question is whether its `sm_120` kernels are actually working in the current WSL2/PyTorch build, hence the Day 1 check.

## Risk register

Weighted rubric used for the review (25% technical risk, 20% feasibility, 20% sim-to-real transfer, 15% complexity/effort, 15% time-to-value, 5% novelty). Raw scores from the two review passes, before the corrections above were applied: defending pass scored 3.35/5.0, attacking pass scored 2.15/5.0. The corrections (official MJCF found, RISE task-list error fixed, GPU resolved) shift the balance closer to the defending pass's estimate on feasibility and technical risk, while the attacking pass's hardware-supply and framing concerns remain valid and are addressed in the task breakdown above.
