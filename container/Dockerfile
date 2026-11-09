FROM docker.io/library/debian:trixie-slim

ARG TARGETARCH
ARG NVIM_VERSION=v0.12.6
ARG NVIM_SHA256_X86_64=474430d53e6264f6d6dd18db42d6dc9df3a1b56ca9e88a325bbf860e1a811d87
ARG NVIM_SHA256_ARM64=8f1f64a0bdb97247034038c3823c6cbad5bdf9ecd5751b85494b71c3ee04c815
ARG TS_PARSERS="bash css gdscript html javascript json lua markdown markdown_inline php python query tsx typescript vim vimdoc"

ENV LANG=C.UTF-8

# /etc/passwd is world-writable so the entrypoint can register an arbitrary runtime uid
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends \
		ca-certificates curl git gzip tar unzip \
		make gcc libc6-dev \
		ncurses-term kitty-terminfo ripgrep \
		nodejs npm \
		python3 python3-pip python3-venv \
		php-cli php-curl php-mbstring php-xml composer \
	&& rm --recursive --force /var/lib/apt/lists/* \
	&& git config --system --add safe.directory '*' \
	&& chmod a+w /etc/passwd

RUN case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
		amd64) arch=x86_64 sha256="$NVIM_SHA256_X86_64" ;; \
		arm64) arch=arm64 sha256="$NVIM_SHA256_ARM64" ;; \
		*) echo "unsupported arch" >&2; exit 1 ;; \
	esac \
	&& curl --fail --location --silent --show-error --output /tmp/nvim.tar.gz \
		"https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${arch}.tar.gz" \
	&& echo "${sha256}  /tmp/nvim.tar.gz" | sha256sum --check --strict \
	&& tar --extract --gzip --file /tmp/nvim.tar.gz --directory /opt \
	&& rm /tmp/nvim.tar.gz \
	&& ln --symbolic "/opt/nvim-linux-${arch}/bin/nvim" /usr/local/bin/nvim

ENV NVIM_CONTAINER=1 \
	XDG_CONFIG_HOME=/nvim/config \
	XDG_DATA_HOME=/nvim/data \
	XDG_STATE_HOME=/nvim/state \
	XDG_CACHE_HOME=/nvim/cache \
	npm_config_cache=/nvim/cache/npm \
	PIP_CACHE_DIR=/nvim/cache/pip \
	COMPOSER_CACHE_DIR=/nvim/cache/composer

COPY --chmod=755 container/entrypoint.sh /usr/local/bin/nvim-entrypoint
COPY container/provision.lua /nvim/provision.lua
COPY init.lua lazy-lock.json /nvim/config/nvim/
COPY snippets /nvim/config/nvim/snippets

RUN NVIM_PROVISION=plugins nvim --headless "+luafile /nvim/provision.lua"
RUN NVIM_PROVISION=fuzzy nvim --headless "+luafile /nvim/provision.lua"
RUN NVIM_PROVISION=tools nvim --headless "+luafile /nvim/provision.lua"
RUN NVIM_PROVISION=parsers nvim --headless "+luafile /nvim/provision.lua"

# runtime runs as the host user's uid; dirs must be writable by any uid
RUN mkdir --parents /nvim/state /nvim/cache \
	&& chmod --recursive a+rwX /nvim \
	&& chmod 1777 /nvim/state /nvim/cache

ENTRYPOINT ["nvim-entrypoint"]
CMD ["nvim"]
