# Shared lab helpers for the test scripts. Sourced, not executed.
#
# Extracted so the hook suite and the worktree suite build their scratch repos the same way.
# Two sets of repo builders that drift apart is how two suites end up disagreeing about what a
# spec repo looks like, and then about which of them is wrong.
#
# Expects $lab to be set to a scratch directory by the caller.

# git with a lab identity, so commits work without touching global config.
g() { git -c user.name=lab -c user.email=lab@example.com -C "$1" "${@:2}"; }

# mkrepo <name> -> prints the path. A main repo with one tracked file and no .specs.
mkrepo() {
  local r="$lab/$1"; mkdir -p "$r"; g "$r" init -q
  echo x > "$r/file.txt"; g "$r" add -A; g "$r" commit -qm init
  echo "$r"
}

# mkspecs <repo> <remote|noremote> <dirty|clean|unpushed>
# Adds the nested spec repo in a chosen state, with a bare remote when asked.
mkspecs() {
  local r="$1" mode="$2" state="$3"
  mkdir -p "$r/.specs"; g "$r/.specs" init -q
  echo spec > "$r/.specs/note.md"; g "$r/.specs" add -A; g "$r/.specs" commit -qm init
  if [ "$mode" = remote ]; then
    git init -q --bare "$r-remote.git"
    g "$r/.specs" remote add origin "$r-remote.git"
    [ "$state" = unpushed ] || g "$r/.specs" push -q -u origin HEAD
  fi
  [ "$state" = dirty ] && echo "uncommitted" > "$r/.specs/dirty.md"
  return 0
}
