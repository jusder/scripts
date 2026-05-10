#!/usr/bin/env zsh
set -u

GITHUB_USER="jusder"
ROOT="$HOME/Coding"

deleted=0
skipped=0

is_target_repo() {
  local remote="$1"
  [[ "$remote" == *"github.com/$GITHUB_USER/"* || "$remote" == *"github.com:$GITHUB_USER/"* ]]
}

handle_repo() {
  local repo="$1"
  local rel="${repo#$ROOT/}"

  git -C "$repo" remote prune origin 2>/dev/null

  local default_branch
  if git -C "$repo" rev-parse --verify main &>/dev/null; then
    default_branch="main"
  elif git -C "$repo" rev-parse --verify master &>/dev/null; then
    default_branch="master"
  else
    return
  fi

  local current_branch
  current_branch="$(git -C "$repo" branch --show-current)"

  local -a merged_branches
  merged_branches=()
  while IFS= read -r line; do
    local b="${line## }"
    b="${b#\* }"
    [[ -z "$b" || "$b" == "main" || "$b" == "master" || "$b" == "$current_branch" ]] && continue
    merged_branches+=("$b")
  done < <(git -C "$repo" branch --merged "$default_branch" 2>/dev/null)

  local -a gone_branches
  gone_branches=()
  while IFS= read -r line; do
    local b="${line##\* }"
    b="${b## }"
    b="${b%% *}"
    [[ -z "$b" || "$b" == "main" || "$b" == "master" || "$b" == "$current_branch" ]] && continue
    local already=0
    for m in "${merged_branches[@]:-}"; do [[ "$m" == "$b" ]] && already=1 && break; done
    (( already )) && continue
    gone_branches+=("$b")
  done < <(git -C "$repo" branch -vv 2>/dev/null | grep ': gone]')

  local -a candidates
  candidates=("${merged_branches[@]:-}" "${gone_branches[@]:-}")
  (( ${#candidates[@]} == 0 )) && return

  echo ""
  echo "== $rel =="
  for b in "${merged_branches[@]:-}"; do echo "  [merged]  $b"; done
  for b in "${gone_branches[@]:-}"; do  echo "  [gone]    $b"; done

  local choice
  read -r "choice?Delete these branches? [y/N] " </dev/tty
  if [[ "${choice:l}" != "y" ]]; then
    echo "Skipped."
    (( skipped += ${#candidates[@]} ))
    return
  fi

  for b in "${candidates[@]}"; do
    if git -C "$repo" branch -d "$b" 2>/dev/null; then
      echo "  Deleted: $b"
      (( deleted++ ))
    else
      echo "  Could not delete: $b (unmerged commits)"
      echo "    To force: git -C '$repo' branch -D '$b'"
      (( skipped++ ))
    fi
  done
}

while IFS= read -r gitdir; do
  repo="${gitdir:h}"
  origin="$(git -C "$repo" remote get-url origin 2>/dev/null)"
  if is_target_repo "$origin"; then
    handle_repo "$repo"
  fi
done < <(find "$ROOT" -name .git -type d -prune)

echo ""
echo "Done: $deleted deleted, $skipped skipped."
