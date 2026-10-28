# Backtalk

A Hacker News reader for iPhone Duo whose rear display roasts what you're
reading. Browse the front page on the inner screen; the outside of the phone
shows the top stories as a magazine, each with a review in the voice of
n-gate.com's *webshit weekly*. Open a thread and the rear turns into a feature
page for it: the headline, a one-line dig at the story, and pull quotes "on"
the commenters. The reviews come from Gemma 4 E4B, fine-tuned with a LoRA and
running on the phone through llama.cpp. Nothing leaves the device except the
Hacker News API calls.

## What works and what doesn't

- **The rear display only works while Backtalk is full screen and unfolded.**
  iOS 27.1's only public route onto the Duo's rear panel is
  `UISceneAccessory.cameraCapture`, which needs a running camera session.
  Backtalk uses the private `+_reservedSceneAccessoryWithConfiguration:`
  (no camera, but the panel is dim) and runs a 1 fps, smallest-format camera
  session to make it bright; the sun button turns the camera off. Both kinds of
  accessory scene are hosted by the app's main scene, so they are torn down
  about 0.4 s after it backgrounds, and in Split View.
- **The rear doesn't rotate on its own.** Backtalk turns the page to follow
  gravity. Which way is up on a panel you look at from behind is a guess, so a
  long press on the rear turns it a quarter, remembered per grip.
- **Reviews are written one at a time**: the ten top front-page stories in the
  background, an opened thread ahead of them. They last for the session.
- **The simulator can't run Gemma 4**: llama.cpp's CPU path aborts in
  `ggml_compute_forward_get_rows_f32`. Model work needs the phone.

## The prompt

Swift (`App/HN.swift`) and Python (`training/threads.py`) build the model's
input character for character the same way, checked on all 1,798 training
threads. The deep prompt takes the ten top-level comments with the biggest
reply trees and follows each down its subthreads, biggest first, within a
7,000-character budget that rolls over from short arguments to the next
(about 1,650 tokens). The first model was trained on a shallower prompt (the
four biggest opening comments, no replies); the app picks the prompt from the
model's filename (`deep` in it or not).

## Training

`training/` scrapes n-gate.com's archive (1,800 entries, 2016-2021, one
request a second), fetches each story's thread from the Algolia HN API, and
trains a rank-16 LoRA on the top 16 layers of `mlx-community/gemma-4-e4b-it-8bit`
with `mlx_lm.lora`, prompt masked. The scraped text and threads are not in this
repository.

```
python3 scrape.py && python3 threads.py && python3 prep.py
.venv/bin/mlx_lm.lora -c lora.yaml            # first stage, shallow prompt
.venv/bin/mlx_lm.lora -c lora-deep.yaml       # second stage, deep prompt
./to-gguf.sh models/ngate-300                 # fuse, convert, Q4_K_M
```

The first stage overfit: validation loss was 3.08 at iteration 300 and 3.54
at 860, so the shipped adapter is the iteration-300 checkpoint. On held-out
stories it has the voice on the prompt it was trained on and wanders off
topic on the deep one ("Gene Cernan has died" came back as a story about
Mozilla), which is why there is a second stage. Training runs at about 60
tokens/s on an M4 Pro, so the deep stage takes hours.

`to-gguf.sh` deletes `extra_special_tokens` from the fused model's
`tokenizer_config.json`: transformers 5 writes it as a list, and the 4.57 that
llama.cpp's converter pins expects a dict.

## Building

Needs `../my_me_bot/Frameworks/llama.xcframework` (llama.cpp built for iOS),
XcodeGen and Xcode 27.

```
scripts/install-duo.sh                    # build, install and launch on a connected Duo
scripts/push-model.sh training/models/gemma-4-E4B-ngate-Q4_K_M.gguf
```

n-gate.com's content is crude, and the model learned that.
