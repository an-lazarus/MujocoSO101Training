#!/bin/bash
rm -rf ~/.cache/huggingface/lerobot/an-lazarus/il_gym_test
python -m lerobot.rl.gym_manipulator \
    --env.name gym_hil \
    --env.task PandaPickCubeKeyboard-v0 \
    --env.fps 30 \
    --dataset.repo_id an-lazarus/il_gym_test \
    --dataset.task pick_cube \
    --dataset.num_episodes_to_record 1 \
    --dataset.push_to_hub false \
    --mode record \
    --device cpu
