#!/usr/bin/env bash
# Downloads an MLX-format model from HuggingFace into a local directory so the
# eval (and MLXCleanup) can load it via loadContainer(from: directory:). We use
# a local dir on purpose — the in-app HF hub loader wants a newer swift-
# transformers that conflicts with WhisperKit's pin. No huggingface-cli needed;
# just curl + python3 to enumerate the repo's files.
#
# Usage:
#   scripts/fetch-eval-model.sh                      # fetches the default set
#   scripts/fetch-eval-model.sh <repo-id> <dest-dir> # fetches one model
set -euo pipefail
cd "$(dirname "$0")/.."

fetch_one() {
  local repo="$1" dest="$2"
  echo "==> $repo -> $dest"
  mkdir -p "$dest"
  # Ask the HF API for the file list, then download each sibling.
  local files
  files=$(curl -fsSL "https://huggingface.co/api/models/$repo" \
    | python3 -c "import sys,json; print('\n'.join(s['rfilename'] for s in json.load(sys.stdin).get('siblings',[])))")
  if [ -z "$files" ]; then
    echo "    !! no files listed for $repo" >&2; return 1
  fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local out="$dest/$f"
    if [ -s "$out" ]; then echo "    skip $f (exists)"; continue; fi
    mkdir -p "$(dirname "$out")"
    echo "    get  $f"
    curl -fL --retry 3 -o "$out" "https://huggingface.co/$repo/resolve/main/$f"
  done <<< "$files"
}

if [ "$#" -eq 2 ]; then
  fetch_one "$1" "$2"
else
  fetch_one "mlx-community/Qwen2.5-0.5B-Instruct-4bit" "eval/models/qwen2.5-0.5b-4bit"
  fetch_one "mlx-community/Qwen2.5-1.5B-Instruct-4bit" "eval/models/qwen2.5-1.5b-4bit"
fi
echo "Done."
