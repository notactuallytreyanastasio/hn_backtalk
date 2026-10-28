#!/bin/zsh
# Trained adapter -> a Gemma 4 E4B GGUF with the n-gate voice baked in, in the
# same Q4_K_M the phone already runs. As in ../my_me_bot: convert_hf_to_gguf.py
# can't read MLX quantization, so fuse with --dequantize first. Intermediates
# are deleted as soon as the next step has what it needs (they are 8-16 GB).
set -euo pipefail
# Usage: to-gguf.sh [adapter dir] [out.gguf]. A name with "deep" in it tells
# the app the model was trained on the deep thread prompt.
cd "${0:A:h}"
# llama.cpp pins an older transformers than mlx-lm needs, so it gets its own env.
py=.venv-convert/bin/python
adapter=${1:-models/ngate-300}
out=${2:-models/gemma-4-E4B-ngate-Q4_K_M.gguf}
.venv/bin/mlx_lm.fuse --model models/gemma-4-e4b-it-8bit --adapter-path $adapter \
  --save-path models/fused-bf16 --dequantize
# transformers 5 writes extra_special_tokens as a list; the converter's 4.57 wants a dict.
$py -c 'import json,sys; p=sys.argv[1]; c=json.load(open(p)); c.pop("extra_special_tokens",None); json.dump(c,open(p,"w"),indent=2)' models/fused-bf16/tokenizer_config.json
$py llama.cpp/convert_hf_to_gguf.py models/fused-bf16 --outtype q8_0 --outfile models/fused-q8_0.gguf
rm -rf models/fused-bf16
llama-quantize --allow-requantize models/fused-q8_0.gguf $out Q4_K_M
rm -f models/fused-q8_0.gguf
ls -la $out
