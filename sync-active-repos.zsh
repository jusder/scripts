#!/usr/bin/env zsh
set -u

ROOT="$HOME/Coding"
SCRIPT_NAME="${0:A:t}"
MODE="${1:-pull}"

GITHUB_USER="jusder"

completed=0
skipped=0
failed=0
found=0

usage() {
  echo "Usage: $SCRIPT_NAME [pull|push|commit-push|status]"
  echo ""
  echo "  pull         Fast-forward pull each clean target repo from its upstream. Default."
  echo "  push         Push each clean target repo to its upstream."
  echo "  commit-push  Prompt to commit local changes, then push each target repo."
  echo "  status       Show compact status for each target repo."
}

if [[ "$MODE" != "pull" && "$MODE" != "push" && "$MODE" != "commit-push" && "$MODE" != "status" ]]; then
  usage
  exit 2
fi

is_target_repo() {
  local remote="$1"
  [[ "$remote" == *"github.com/$GITHUB_USER/"* || "$remote" == *"github.com:$GITHUB_USER/"* ]]
}

push_repo() {
  local repo="$1"
  local branch="$2"
  local upstream="$3"

  echo "Fetching $upstream..."
  if ! git -C "$repo" fetch 2>/dev/null; then
    echo "Failed: could not fetch from remote"
    (( failed++ ))
    return
  fi

  local behind ahead
  behind="$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null)"
  ahead="$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null)"

  if (( behind > 0 && ahead > 0 )); then
    echo "Skipped: diverged from remote ($ahead ahead, $behind behind). Resolve manually."
    (( skipped++ ))
    return
  elif (( behind > 0 )); then
    echo "Skipped: remote is $behind commit(s) ahead. Pull before pushing."
    (( skipped++ ))
    return
  elif (( ahead == 0 )); then
    echo "Already up to date, nothing to push."
    (( completed++ ))
    return
  fi

  echo "Pushing $branch to $upstream..."
  if git -C "$repo" push; then
    (( completed++ ))
  else
    echo "Failed: push did not complete"
    (( failed++ ))
  fi
}

commit_changes() {
  local repo="$1"
  local rel="$2"
  local stage_choice
  local commit_message
  local default_message="Update $rel"

  echo "Choose what to stage for $rel."
  read -r "stage_choice?Stage [a]ll changes, [t]racked changes only, or [s]kip? [s] " </dev/tty

  case "${stage_choice:l}" in
    a|all)
      if ! git -C "$repo" add -A; then
        echo "Failed: could not stage changes"
        (( failed++ ))
        return 1
      fi
      ;;
    t|tracked)
      if ! git -C "$repo" add -u; then
        echo "Failed: could not stage tracked changes"
        (( failed++ ))
        return 1
      fi
      ;;
    *)
      echo "Skipped: commit declined"
      (( skipped++ ))
      return 1
      ;;
  esac

  if git -C "$repo" diff --cached --quiet; then
    echo "Skipped: no staged changes to commit"
    (( skipped++ ))
    return 1
  fi

  read -r "commit_message?Commit message [$default_message]: " </dev/tty
  if [[ -z "$commit_message" ]]; then
    commit_message="$default_message"
  fi

  if ! git -C "$repo" commit -m "$commit_message"; then
    echo "Failed: commit did not complete"
    (( failed++ ))
    return 1
  fi

  return 0
}

handle_repo() {
  local repo="$1"
  local rel="${repo#$ROOT/}"
  local branch
  local upstream
  local has_changes

  (( found++ ))

  echo ""
  echo "== $rel =="
  git -C "$repo" status --short --branch

  branch="$(git -C "$repo" branch --show-current)"

  if [[ "$MODE" == "status" ]]; then
    (( completed++ ))
    return
  fi

  if [[ -z "$branch" ]]; then
    echo "Skipped: detached HEAD"
    (( skipped++ ))
    return
  fi

  upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
  if [[ -z "$upstream" ]]; then
    echo "Skipped: branch '$branch' has no upstream"
    (( skipped++ ))
    return
  fi

  has_changes="$(git -C "$repo" status --porcelain)"

  if [[ -n "$has_changes" ]]; then
    if [[ "$MODE" == "commit-push" ]]; then
      commit_changes "$repo" "$rel" || return
    elif [[ "$MODE" == "pull" ]]; then
      local stash_choice
      read -r "stash_choice?Local changes present. Stash, pull, then unstash? [y/N] " </dev/tty
      if [[ "${stash_choice:l}" == "y" ]]; then
        if ! git -C "$repo" stash push -m "sync-script auto-stash"; then
          echo "Failed: could not stash changes"
          (( failed++ ))
          return
        fi
        echo "Pulling $branch from $upstream..."
        if git -C "$repo" pull --ff-only; then
          (( completed++ ))
        else
          echo "Failed: pull did not complete"
          (( failed++ ))
        fi
        echo "Restoring stash..."
        if ! git -C "$repo" stash pop; then
          echo "Warning: stash pop failed — run 'git stash pop' manually in $rel"
        fi
        return
      else
        echo "Skipped: local changes present. Commit or stash before syncing."
        (( skipped++ ))
        return
      fi
    else
      echo "Skipped: local changes present. Commit or stash before syncing."
      (( skipped++ ))
      return
    fi
  elif [[ "$MODE" == "commit-push" ]]; then
    echo "No local changes to commit."
  fi

  case "$MODE" in
    pull)
      echo "Pulling $branch from $upstream..."
      if git -C "$repo" pull --ff-only; then
        (( completed++ ))
      else
        echo "Failed: pull did not complete"
        (( failed++ ))
      fi
      ;;
    push|commit-push)
      push_repo "$repo" "$branch" "$upstream"
      ;;
  esac
}

while IFS= read -r gitdir; do
  repo="${gitdir:h}"
  origin="$(git -C "$repo" remote get-url origin 2>/dev/null)"

  if is_target_repo "$origin"; then
    handle_repo "$repo"
  fi
done < <(find "$ROOT" -name .git -type d -prune)

if (( found == 0 )); then
  echo "No target repos found under $ROOT."
fi

echo ""
echo "Done: $completed completed, $skipped skipped, $failed failed."

if (( failed > 0 )); then
  exit 1
fi
