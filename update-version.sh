#!/usr/bin/env -S nix shell nixpkgs#bash nixpkgs#curl nixpkgs#jq nixpkgs#nix --command bash

# Re-pins pin.nix to a commit of the HuggingFace repo cross-encoder/ms-marco-MiniLM-L6-v2 and recomputes the per-file hashes.
#
#   nix run .#update-version            # latest commit on main
#   nix run .#update-version -- <sha>   # a specific commit
#
# Always recomputes and rewrites, so it doubles as a "re-validate this exact pin" pass.

set -euo pipefail

FLAKE_ROOT="${FLAKE_ROOT:-${PWD}}"
pin="${FLAKE_ROOT}/pin.nix"
repo="cross-encoder/ms-marco-MiniLM-L6-v2"
# The subset CrossEncoder needs — keep in sync with flake.nix's expectations.
files=(config.json model.safetensors tokenizer.json tokenizer_config.json special_tokens_map.json vocab.txt)

if [[ ! -f "${pin}" ]]; then
  echo "error: no pin.nix in ${FLAKE_ROOT} (run from the flake root or set FLAKE_ROOT)" >&2
  exit 1
fi

if [[ $# -ge 1 && -n "${1}" ]]; then
  rev="${1}"
else
  echo "Resolving latest commit of ${repo}..."
  rev=$(curl -sL "https://huggingface.co/api/models/${repo}" | jq -r '.sha')
fi
[[ -n "${rev}" && "${rev}" != "null" ]] || { echo "error: could not resolve a commit" >&2; exit 1; }

cur_rev=$(nix eval --raw --file "${pin}" rev 2>/dev/null || echo "")
echo "  current: ${cur_rev:-<empty>}"
echo "  target:  ${rev}"

declare -A newh
for f in "${files[@]}"; do
  echo "  prefetch ${f}..."
  newh["${f}"]=$(nix store prefetch-file --json "https://huggingface.co/${repo}/resolve/${rev}/${f}" | jq -r '.hash')
done

cur_hashes=$(nix eval --json --file "${pin}" hashes 2>/dev/null || echo '{}')
unchanged=1
[[ "${cur_rev}" == "${rev}" ]] || unchanged=0
for f in "${files[@]}"; do
  cur=$(printf '%s' "${cur_hashes}" | jq -r --arg k "${f}" '.[$k] // ""')
  [[ "${cur}" == "${newh[${f}]}" ]] || unchanged=0
done
[[ "${unchanged}" == 1 ]] && echo "Already up to date (${rev})."

{
  echo "# Auto-managed by \`nix run .#update-version\`. Manual edits will be overwritten by the next bump."
  echo "{"
  echo "  rev = \"${rev}\";"
  echo "  # Per-file sha256 of the subset of HF repo files CrossEncoder needs (skips onnx/openvino/flax/pytorch_model.bin)."
  echo "  hashes = {"
  for f in "${files[@]}"; do echo "    \"${f}\" = \"${newh[${f}]}\";"; done
  echo "  };"
  echo "}"
} > "${pin}"

echo "Verifying build..."
nix build --option post-build-hook "" "${FLAKE_ROOT}#model" --no-link

echo
echo "Pinned ${repo} @ ${rev}."
echo "  Review pin.nix / the root flake.lock."
