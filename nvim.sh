#!/usr/bin/env bash
# Containerized neovim. Only host dependency: podman (preferred) or docker.
#
#   nvim.sh [nvim args...]   run nvim (auto-builds image when container/ or lazy-lock.json change)
#   nvim.sh build            force rebuild
#   nvim.sh shell [bash args...]  bash inside the container
#   nvim.sh clean            remove image + all volumes (plugins, undo history)
#   nvim.sh install          symlink ${XDG_BIN_HOME:-~/.local/bin}/nvim -> nvim.sh (works for git, $EDITOR, etc.)
# NVIM_CONTAINER_RUNTIME=docker|podman overrides runtime detection.
#
# Mounts (at identical paths): $HOME, plus for each path argument / $PWD outside $HOME
# its project dir: enclosing git repo, else the directory itself / the file's directory
# (init.lua cds by the same rule). Files under container system paths are mounted individually.
# Bash 3.2 compatible (macOS).
set -o errexit -o nounset -o pipefail

CONFIG_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
readonly CONFIG_DIR
readonly IMAGE=localhost/nvim-container
readonly LABEL=nvim-container
readonly INPUTS_LABEL="$LABEL.inputs"
readonly STATE_VOLUME="$LABEL-state"
readonly LOCK_DIR="${TMPDIR:-/tmp}/$LABEL-$(id -u).lock"

# directory trees the container itself needs; host dirs must not shadow them
SYSTEM_TREES=(/bin /boot /dev /etc /lib /lib64 /nvim /opt /proc /run /sbin /sys /usr)
# directories too broad to mount whole
SYSTEM_DIRS=(/ /home /private /root /Users /var)
# files the runtime or entrypoint manages
RUNTIME_FILES=(/etc/group /etc/hostname /etc/hosts /etc/passwd /etc/resolv.conf /etc/shadow)

warn() {
	echo "nvim.sh: $*" >&2
}

detect_runtime() {
	if [[ -n "${NVIM_CONTAINER_RUNTIME:-}" ]]; then
		echo "$NVIM_CONTAINER_RUNTIME"
	elif command -v podman >/dev/null; then
		echo podman
	elif command -v docker >/dev/null; then
		echo docker
	else
		warn "podman or docker required"
		exit 1
	fi
}
RUNTIME="$(detect_runtime)"
readonly RUNTIME

runtime() {
	"$RUNTIME" "$@"
}

#########
# IMAGE #
#########

build_inputs_hash() {
	cat "$CONFIG_DIR"/container/* "$CONFIG_DIR/lazy-lock.json" | cksum | cut -d ' ' -f 1
}

image_inputs_hash() {
	runtime image inspect --format "{{index .Config.Labels \"$INPUTS_LABEL\"}}" "$IMAGE" 2>/dev/null || true
}

image_is_current() {
	[[ "$(image_inputs_hash)" == "$(build_inputs_hash)" ]]
}

image_id() {
	runtime image inspect --format '{{.Id}}' "$IMAGE" | sed 's/^sha256://' | cut -c 1-12
}

release_build_lock() {
	rm -rf "$LOCK_DIR"
	trap - EXIT
}

# mkdir is atomic on every platform; a lock whose holder died is reclaimed
acquire_build_lock() {
	local holder
	until mkdir "$LOCK_DIR" 2>/dev/null; do
		holder="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
		if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
			rm -rf "$LOCK_DIR"
			continue
		fi
		sleep 1
	done
	echo $$ >"$LOCK_DIR/pid"
	trap release_build_lock EXIT
}

# keyed per image so a rebuild repopulates plugins/tools from the new image
data_volume() {
	echo "$LABEL-data-$(image_id)"
}

remove_stale_data_volumes() {
	local current volume
	current="$(data_volume)"
	for volume in $(runtime volume ls --quiet --filter "label=$LABEL=data"); do
		[[ "$volume" == "$current" ]] || runtime volume rm "$volume" >/dev/null 2>&1 || true
	done
	runtime image prune --force --filter "label=$INPUTS_LABEL" >/dev/null
}

build_locked() {
	runtime build \
		--file "$CONFIG_DIR/container/Dockerfile" \
		--tag "$IMAGE" \
		--label "$INPUTS_LABEL=$(build_inputs_hash)" \
		"$CONFIG_DIR"
	remove_stale_data_volumes
}

build() {
	acquire_build_lock
	build_locked
	release_build_lock
}

ensure_image() {
	image_is_current && return
	acquire_build_lock
	image_is_current || build_locked
	release_build_lock
}

ensure_volume() {
	runtime volume inspect "$1" >/dev/null 2>&1 || runtime volume create --label "$LABEL=$2" "$1" >/dev/null
}

##########
# MOUNTS #
##########

is_within() {
	local path="$1" ancestor="$2"
	[[ "$path" == "$ancestor" || "$path" == "${ancestor%/}"/* ]]
}

is_system_path() {
	local path="$1" entry
	for entry in "${SYSTEM_DIRS[@]}"; do
		[[ "$path" == "$entry" ]] && return 0
	done
	for entry in "${SYSTEM_TREES[@]}"; do
		is_within "$path" "$entry" && return 0
	done
	return 1
}

is_runtime_file() {
	local path="$1" entry
	for entry in "${RUNTIME_FILES[@]}"; do
		[[ "$path" == "$entry" ]] && return 0
	done
	return 1
}

# logical (symlinks kept) so the path matches what nvim is given
absolute_path() {
	local path="$1"
	[[ "$path" == /* ]] || path="$PWD/$path"
	local dir="$path" suffix=""
	until [[ -d "$dir" ]]; do
		suffix="/$(basename "$dir")$suffix"
		dir="$(dirname "$dir")"
	done
	echo "$(cd "$dir" && pwd)$suffix"
}

nearest_existing_dir() {
	local dir="$1"
	[[ -d "$dir" ]] || dir="$(dirname "$dir")"
	until [[ -d "$dir" ]]; do
		dir="$(dirname "$dir")"
	done
	echo "$dir"
}

git_root() {
	local dir="$1"
	while true; do
		if [[ -e "$dir/.git" ]] && ! is_system_path "$dir"; then
			echo "$dir"
			return 0
		fi
		[[ "$dir" == / ]] && return 1
		dir="$(dirname "$dir")"
	done
}

# worktrees/submodules have a .git file pointing at a git dir elsewhere; git needs it too
external_git_dir() {
	local root="$1" git_dir
	[[ -f "$root/.git" ]] || return 0
	git_dir="$(sed -n 's/^gitdir: //p' "$root/.git")"
	[[ "$git_dir" == /* ]] || git_dir="$root/$git_dir"
	[[ -d "$git_dir" ]] || return 0
	if [[ -f "$git_dir/commondir" ]]; then
		git_dir="$git_dir/$(cat "$git_dir/commondir")"
	fi
	(cd "$git_dir" && pwd)
}

# same rule as init.lua's project dir: git repo, else opened dir, else file's dir
project_root() {
	local path="$1" dir
	dir="$(nearest_existing_dir "$path")"
	git_root "$dir" || {
		is_system_path "$dir" || echo "$dir"
	}
}

# prints host paths to mount for $1 (none when covered by $HOME / unmountable)
mount_sources() {
	local path root
	path="$(absolute_path "$1")"
	is_within "$path" "$HOME" && return
	root="$(project_root "$path" || true)"
	if [[ -n "$root" ]]; then
		echo "$root"
		external_git_dir "$root"
	elif [[ -f "$path" ]] && ! is_runtime_file "$path"; then
		echo "$path"
	else
		warn "not mounting system path $path; nvim will see the container's copy"
	fi
}

# file-ish arguments of nvim's CLI, one per line
nvim_path_args() {
	local arg next="" literal=false
	for arg in "$@"; do
		if [[ -n "$next" ]]; then
			if [[ "$next" == path ]]; then
				echo "$arg"
			fi
			next=""
		elif $literal; then
			echo "$arg"
		else
			case "$arg" in
				--) literal=true ;;
				-c | --cmd | --listen | -t) next=value ;;
				-i | -q | -s | -S | -u | -w | -W | --startuptime) next=path ;;
				-* | +*) ;;
				*) echo "$arg" ;;
			esac
		fi
	done
}

MOUNTS=()
add_mount() {
	local source="$1" existing
	for existing in "$HOME" ${MOUNTS[@]+"${MOUNTS[@]}"}; do
		is_within "$source" "$existing" && return
	done
	MOUNTS+=("$source")
}

collect_mounts() {
	local path source
	while IFS= read -r path; do
		[[ -n "$path" ]] || continue
		while IFS= read -r source; do
			add_mount "$source"
		done < <(mount_sources "$path")
	done < <(echo "$PWD"; nvim_path_args "$@")
}

#######
# RUN #
#######

RUN_ARGS=()

add_user_args() {
	if [[ "$RUNTIME" == podman ]]; then
		# keep-id maps the host uid in; SELinux relabeling of $HOME would be destructive
		RUN_ARGS+=(--userns=keep-id --security-opt label=disable)
	else
		RUN_ARGS+=(--user "$(id -u):$(id -g)")
	fi
}

add_network_args() {
	if [[ "$(uname -s)" == Darwin ]]; then
		RUN_ARGS+=(--env NVIM_HOST_ADDR=host.docker.internal)
	else
		RUN_ARGS+=(--network host)
	fi
}

# zoneinfo symlink target is .../zoneinfo/<Area/City> on both Linux and macOS
add_timezone_args() {
	local timezone="${TZ:-}"
	if [[ -z "$timezone" && -L /etc/localtime ]]; then
		timezone="$(readlink /etc/localtime | sed -n 's|.*/zoneinfo/||p')"
	fi
	if [[ -n "$timezone" ]]; then
		RUN_ARGS+=(--env TZ="$timezone")
	fi
}

STDIN_SPOOL=""
# a container can't take both a pipe and a tty, so the pipe is handed over as a file
spool_piped_stdin() {
	[[ -t 1 && ! -t 0 ]] || return 0
	STDIN_SPOOL="$(mktemp "${TMPDIR:-/tmp}/$LABEL-stdin.XXXXXX")"
	cat >"$STDIN_SPOOL"
	RUN_ARGS+=(--volume "$STDIN_SPOOL:/nvim/stdin:ro" --env NVIM_CONTAINER_STDIN=/nvim/stdin)
}

add_mount_args() {
	local volume="$1" source
	RUN_ARGS+=(
		--volume "$HOME:$HOME"
		--volume "$CONFIG_DIR:/nvim/config/nvim"
		--volume "$volume:/nvim/data"
		--volume "$STATE_VOLUME:/nvim/state"
	)
	for source in ${MOUNTS[@]+"${MOUNTS[@]}"}; do
		RUN_ARGS+=(--volume "$source:$source")
	done
}

run_container() {
	ensure_image
	local volume
	volume="$(data_volume)"
	ensure_volume "$volume" data
	ensure_volume "$STATE_VOLUME" state

	RUN_ARGS=(
		--rm --interactive --init
		--detach-keys "ctrl-@,ctrl-@"
		--env HOME="$HOME" --env USER
		--env TERM --env COLORTERM
		--env NVIM_OLLAMA_MODEL --env PHP_VERSION --env GDScript_Port
		--workdir "$PWD"
	)
	add_user_args
	add_network_args
	add_timezone_args
	add_mount_args "$volume"
	spool_piped_stdin

	if [[ -n "$STDIN_SPOOL" ]]; then
		local status=0
		runtime run --tty "${RUN_ARGS[@]}" "$IMAGE" "$@" </dev/tty || status=$?
		rm -f "$STDIN_SPOOL"
		return "$status"
	fi
	if [[ -t 0 && -t 1 ]]; then
		RUN_ARGS+=(--tty)
	fi
	runtime run "${RUN_ARGS[@]}" "$IMAGE" "$@"
}

install_link() {
	local bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}" target="$CONFIG_DIR/nvim.sh" link resolved
	link="$bin_dir/nvim"
	if [[ -e "$link" || -L "$link" ]] && [[ "$(readlink "$link")" != "$target" ]]; then
		warn "$link already exists and isn't a link to $target; remove it first"
		exit 1
	fi
	mkdir -p "$bin_dir"
	ln -sf "$target" "$link"
	echo "linked $link -> $target"
	resolved="$(command -v nvim || true)"
	if [[ "$resolved" != "$link" ]]; then
		warn "PATH resolves nvim to ${resolved:-nothing}; put $bin_dir before it in PATH"
	fi
}

clean() {
	local volume
	runtime image rm --force "$IMAGE" 2>/dev/null || true
	for volume in $(runtime volume ls --quiet --filter "label=$LABEL"); do
		runtime volume rm "$volume" >/dev/null
	done
}

case "${1:-}" in
	build) build ;;
	shell)
		shift
		collect_mounts
		run_container bash "$@"
		;;
	clean) clean ;;
	install) install_link ;;
	*)
		collect_mounts "$@"
		run_container nvim "$@"
		;;
esac
