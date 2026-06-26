#!/bin/bash
# Validated record-mode launch (WSL2 Ubuntu 24.04, CPU, software GL).
# If copied onto the WSL side from this Windows path, normalise line endings first:
#   sed -i 's/\r$//' record.sh
#
# WSLg rendering: force CPU software GL. GPU (Zink/D3D12) segfaults; MUJOCO_GL=osmesa
# breaks the interactive viewer. See CHANGES.md / CLAUDE.md.
export MUJOCO_GL=glfw
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

rm -rf ~/.cache/huggingface/lerobot/an-lazarus/il_gym_test

"$HOME/mujoco-sim/.venv/bin/python" -m lerobot.rl.gym_manipulator \
    --env.name gym_hil \
    --env.task PandaPickCubeKeyboard-v0 \
    --env.fps 30 \
    --dataset.repo_id an-lazarus/il_gym_test \
    --dataset.task pick_cube \
    --dataset.num_episodes_to_record 1 \
    --dataset.push_to_hub false \
    --mode record \
    --device cpu
