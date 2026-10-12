#!/usr/bin/env bash
# End-to-end check of bin/punch against a throwaway corpus under a private
# HOME. Run from the repo root: bash test/cli.sh (make test).
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export XDG_CONFIG_HOME=$HOME/.config
mkdir -p "$XDG_CONFIG_HOME/punch" "$HOME/work"
printf '~/punch\n~/work\n' >"$XDG_CONFIG_HOME/punch/corpus"
punch() { "$root/bin/punch" "$@"; }

failed=0
check() { # name, condition...
  local name=$1; shift
  if "$@"; then :; else failed=$((failed + 1)); echo "FAIL $name" >&2; fi
}
has() { grep -q -- "$2" <<<"$1"; }
lacks() { ! grep -q -- "$2" <<<"$1"; }

today=$(date +%F)
later=$(date -d '+10 days' +%F)
cat >"$HOME/work/TODO.md" <<EOF
# Project
owner: jake

## TODO Pour the footing
deadline: 2000-01-01

## TODO Order rebar
scheduled: $later

## DONE Survey the lot
closed: 2026-01-01T09:00

- [ ] loose item
EOF

# capture
out=$(punch "Buy lumber" -t '#site' -s today)
check "capture echoes location" has "$out" '^~/punch/inbox.md:1  # TODO Buy lumber #site$'
check "capture scheduled" grep -qx "scheduled: $today" "$HOME/punch/inbox.md"
out=$(punch -d +1w -- done the dishes) # after -- every word is text
check "capture after --" grep -qx '# TODO done the dishes' "$HOME/punch/inbox.md"
check "bad date rejected" lacks "$(punch oops -s whenever 2>&1)" 'inbox.md'

# inbox
out=$(punch inbox)
check "inbox count" has "$out" '^2 in ~/punch/inbox.md$'
check "inbox lists" has "$out" 'done the dishes'

# agenda
out=$(punch agenda)
check "agenda late" has "$out" '^late   2000-01-01  deadline   TODO Pour the footing'
check "agenda today" has "$out" "^today  $today  scheduled  TODO Buy lumber #site"
check "agenda hides future" lacks "$out" 'Order rebar'
check "agenda checkboxes" has "$out" '^~/work/TODO.md:13  loose item$'
check "agenda week hides +10d" lacks "$(punch agenda week)" 'Order rebar'
check "agenda all shows +10d" has "$(punch agenda all)" "$later  scheduled  TODO Order rebar"

# list
check "list by tag" has "$(punch list '#site')" 'Buy lumber'
check "list by tag excludes" lacks "$(punch list '#site')" 'footing'
check "list by state" has "$(punch list DONE)" 'Survey the lot'
check "list open only" lacks "$(punch list)" 'Survey the lot'

# done
out=$(punch done ~/punch/inbox.md:2) # a field line resolves to its heading
check "done cycles" has "$out" '^~/punch/inbox.md:1  # DONE Buy lumber #site$'
check "done stamps" grep -q "^closed: $today" "$HOME/punch/inbox.md"

# refile
loc=$(punch list | grep dishes | cut -d' ' -f1)
out=$(punch refile "$loc" ~/work/TODO.md project)
check "refile reports" has "$out" '^done the dishes -> ~/work/TODO.md:1$'
check "refile lands nested" grep -qx '## TODO done the dishes' "$HOME/work/TODO.md"
check "refile removes" lacks "$(cat "$HOME/punch/inbox.md")" 'dishes'
check "refile into own subtree" lacks "$(punch refile ~/work/TODO.md:1 ~/work/TODO.md footing 2>&1)" '->'

# check
echo 'See [[nowhere]].' >>"$HOME/work/TODO.md"
out=$(punch check); status=$?
check "check fails" [ "$status" -eq 1 ]
check "check names link" has "$out" 'dangling link \[\[nowhere\]\]'
sed -i '$d' "$HOME/work/TODO.md"
check "check ok" has "$(punch check)" '^ok: 2 files'

if [ "$failed" -eq 0 ]; then echo "cli ok"; else echo "cli: $failed failed"; exit 1; fi
