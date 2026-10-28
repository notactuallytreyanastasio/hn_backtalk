#!/bin/zsh
# Copies a Gemma GGUF into Backtalk's Documents on the iPhone Duo.
# Default: my_me_bot's Gemma 4 E4B (Q4_K_M, 4.6 GB). Takes a few minutes by cable.
set -euo pipefail
model=${1:-$HOME/code/my_me_bot/models/gemma-4-E4B-it-Q4_K_M.gguf}
duo=${2:-00008160-001E042614700036}
xcrun devicectl device copy to --device "$duo" --domain-type appDataContainer \
  --domain-identifier com.bgrayson.backtalk --source "$model" --destination "Documents/${model:t}"
