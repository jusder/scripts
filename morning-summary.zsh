#!/usr/bin/env zsh
set -u

GITHUB_USER="jusder"
ROOT="$HOME/Coding"

FETCH=0
if [[ "${1:-}" == "--fetch" ]]; then
  FETCH=1
fi

found=0

is_target_repo() {
  local remote="$1"
  [[ "$remote" == *"github.com/$GITHUB_USER/"* || "$remote" == *"github.com:$GITHUB_USER/"* ]]
}

handle_repo() {
  local repo="$1"
  local rel="${repo#$ROOT/}"
  (( found++ ))

  if (( FETCH )); then
    git -C "$repo" fetch --quiet 2>/dev/null
  fi

  local branch
  branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
  [[ -z "$branch" ]] && branch="(detached)"

  local ahead behind ab_str
  ahead="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null)"
  behind="$(git -C "$repo" rev-list --count 'HEAD..@{u}' 2>/dev/null)"
  if [[ -z "$ahead" && -z "$behind" ]]; then
    ab_str="no upstream"
  else
    ab_str="+${ahead}/-${behind}"
  fi

  local change_count
  change_count="$(git -C "$repo" status --porcelain 2>/dev/null | grep -cv '^??' || true)"

  local last_commit
  last_commit="$(git -C "$repo" log -1 --format="%ar: %s" 2>/dev/null)"
  [[ -z "$last_commit" ]] && last_commit="(no commits)"

  printf "%-30s  %-12s  %-12s  %s change(s)  %s\n" \
    "$rel" "$branch" "$ab_str" "$change_count" "$last_commit"
}

echo ""
printf "=== Repo Summary — %s ===\n" "$(date '+%a %b %d')"
echo ""
printf "%-30s  %-12s  %-12s  %-12s  %s\n" "REPO" "BRANCH" "↑/↓" "CHANGES" "LAST COMMIT"
printf '%0.s-' {1..95}
echo ""

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
if (( ! FETCH )); then
  echo "Note: ahead/behind reflects local knowledge only. Run with --fetch for current data."
fi
echo "Total: $found repo(s)."
