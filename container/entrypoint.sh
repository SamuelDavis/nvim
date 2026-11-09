#!/bin/sh
set -o errexit -o nounset

# rootful docker runs as a uid absent from /etc/passwd; git/ssh/pip expect a named user
if ! getent passwd "$(id -u)" >/dev/null; then
	echo "${USER:-nvim}:x:$(id -u):$(id -g)::${HOME}:/bin/bash" >>/etc/passwd
fi

# host terminals may be newer than the image's terminfo database
if ! infocmp "${TERM:-dumb}" >/dev/null 2>&1; then
	export TERM=xterm-256color
fi

# piped stdin arrives spooled to a file (see nvim.sh); nvim reads keys from the tty on stderr
if [ -n "${NVIM_CONTAINER_STDIN:-}" ]; then
	exec "$@" <"$NVIM_CONTAINER_STDIN"
fi

exec "$@"
