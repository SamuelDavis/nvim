#!/usr/bin/env bash
# Black-box tests for nvim.sh's pre-container guards (root files, root user, unmountable paths).
# The container runtime is a stub that fails loudly, so no case can launch nvim.
# Usage: test/guards.sh   (macOS + Linux; needs /etc/hosts, /etc/passwd owned by root)
set -o nounset -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
readonly SCRIPT="$REPO/nvim.sh"
SCRATCH="$(mktemp -d)"
readonly SCRATCH
trap 'rm -rf "$SCRATCH"' EXIT

readonly RUNTIME_STUB="$SCRATCH/runtime"
printf '#!/bin/sh\necho "RUNTIME CALLED: $*" >&2\nexit 99\n' >"$RUNTIME_STUB"
chmod +x "$RUNTIME_STUB"

readonly ROOT_ID_BIN="$SCRATCH/root-id-bin"
mkdir "$ROOT_ID_BIN"
printf '#!/bin/sh\n[ "$1" = -u ] && { echo 0; exit 0; }\nexec %s "$@"\n' "$(command -v id)" >"$ROOT_ID_BIN/id"
chmod +x "$ROOT_ID_BIN/id"

readonly NO_VIM_BIN="$SCRATCH/no-vim-bin"
mkdir "$NO_VIM_BIN"
for tool in bash basename cat dirname find id readlink sudo; do
	ln -s "$(PATH=/usr/bin:/bin command -v "$tool")" "$NO_VIM_BIN/$tool"
done

readonly LINK="$SCRATCH/hosts-link"
ln -s /etc/hosts "$LINK"
readonly USER_FILE="$SCRATCH/user-file"
touch "$USER_FILE"

failures=0
STATUS=0 OUT="" ERR=""

run() {
	STATUS=0
	(cd "$REPO" && env NVIM_CONTAINER_RUNTIME="$RUNTIME_STUB" "$@") \
		>"$SCRATCH/out" 2>"$SCRATCH/err" </dev/null || STATUS=$?
	OUT="$(cat "$SCRATCH/out")"
	ERR="$(cat "$SCRATCH/err")"
}

check() {
	local name="$1" expected_status="$2" expected_out="$3" err_pattern="$4"
	if [[ "$STATUS" == "$expected_status" && "$OUT" == "$expected_out" && "$ERR" == *$err_pattern* && "$ERR" != *"RUNTIME CALLED"* ]]; then
		echo "ok   $name"
		return
	fi
	failures=$((failures + 1))
	printf 'FAIL %s\n  status: %s (want %s)\n  stdout: %s\n  want:   %s\n  stderr: %s\n  want ~: %s\n' \
		"$name" "$STATUS" "$expected_status" "$OUT" "$expected_out" "$ERR" "$err_pattern"
}

readonly EDIT="SUDO_EDITOR='vim --clean' sudo --edit --"

run "$SCRIPT" /etc/hosts
check "root file prints sudo --edit command" 1 "$EDIT /etc/hosts" "root-owned"

run "$SCRIPT" /etc/hosts /etc/passwd
check "multiple root files" 1 "$EDIT /etc/hosts /etc/passwd" "root-owned"

run "$SCRIPT" "/etc/nvim-sh test-missing"
check "new file in root dir, quoted" 1 "$EDIT /etc/nvim-sh\\ test-missing" "root-owned"

run bash -c "cd /etc && '$SCRIPT' hosts"
check "relative root file" 1 "$EDIT hosts" "root-owned"

run "$SCRIPT" -R /etc/hosts
check "root file with flag" 1 "" "only arguments"

run "$SCRIPT" -- /etc/hosts
check "root file after --" 1 "" "only arguments"

run "$SCRIPT" /etc/hosts "$USER_FILE"
check "root file mixed with user file" 1 "" "only arguments"

run "$SCRIPT" /etc
check "root directory" 1 "" "can't safely"

run "$SCRIPT" "$LINK"
check "symlink to root file" 1 "" "can't safely"

run env PATH="$NO_VIM_BIN" "$SCRIPT" /etc/hosts
check "root file without vim" 1 "" "vim"

run env PATH="$ROOT_ID_BIN:$PATH" "$SCRIPT" "$USER_FILE"
check "running as root" 1 "" "refusing to run as root"

run "$SCRIPT" /usr/nvim-sh-test-missing/file
check "unmountable system path" 1 "" "not mounting system path"

((failures == 0)) || { echo "$failures failed"; exit 1; }
echo "all passed"
