#!/usr/bin/env bash
# 42-wizzard for Ubuntu — the set of tools you don't know you need, no sudo required.
# Works when sourced from ~/.bashrc or ~/.zshrc (the installer does this) or run directly:
#   42 -h          (after sourcing)
#   bash 42-wizzard.sh -h

WIZZARD_VERSION="1.0.0"
: "${USER:=$(id -un)}"
WIZZARD_FILE="$HOME/.42-wizzard.sh"
WIZZARD_CONF="$HOME/.42-wizzard.conf"
WIZZARD_LOG="${TMPDIR:-/tmp}/42-wizzard-$USER.log"
WIZZARD_APT_ROOT="${WIZZARD_APT_ROOT:-$HOME/.local/apt}"
# shellcheck disable=SC1090
[ -f "$WIZZARD_CONF" ] && . "$WIZZARD_CONF"

WZ_RESET=$'\e[0m'
WZ_RED=$'\e[1;31m'
WZ_GREEN=$'\e[1;32m'
WZ_YELLOW=$'\e[1;33m'
WZ_BLUE=$'\e[1;34m'
WZ_ANIMATION_RATE=0.3

WZ_METRO=('[                        ]' '[=                       ]' '[==                      ]'
	'[===                     ]' '[====                    ]' '[=====                   ]'
	'[======                  ]' '[=======                 ]' '[========                ]'
	'[=========               ]' '[==========              ]' '[===========             ]'
	'[============            ]' '[ ============           ]' '[  ============          ]'
	'[   ============         ]' '[    ============        ]' '[     ============       ]'
	'[      ============      ]' '[       ============     ]' '[        ============    ]'
	'[         ============   ]' '[          ============  ]' '[           ============ ]'
	'[            ============]' '[             ===========]' '[              ==========]'
	'[               =========]' '[                ========]' '[                 =======]'
	'[                  ======]' '[                   =====]' '[                    ====]'
	'[                     ===]' '[                      ==]' '[                       =]')

# ───────────────────────────── helpers ─────────────────────────────

_wz_ok()   { printf '%s✔%s %s\n' "$WZ_GREEN" "$WZ_RESET" "$*"; }
_wz_warn() { printf '%s!%s %s\n' "$WZ_YELLOW" "$WZ_RESET" "$*"; }
_wz_err()  { printf '%s✘%s %s\n' "$WZ_RED" "$WZ_RESET" "$*" >&2; }

# loading animation: runs in a detached subshell so no job-control noise in bash or zsh
_wz_spin_loop() {
	local frame
	while :; do
		for frame in "$@"; do
			printf '\r%s ' "$frame"
			sleep "$WZ_ANIMATION_RATE"
		done
	done
}

_wz_spin_start() {
	WZ_SPIN_PID=""
	[ -t 1 ] || return 0
	tput civis 2>/dev/null
	WZ_SPIN_PID=$( (_wz_spin_loop "$@" </dev/null >/dev/tty 2>&1 & echo $!) )
}

_wz_spin_stop() {
	[ -n "${WZ_SPIN_PID:-}" ] || return 0
	kill "$WZ_SPIN_PID" 2>/dev/null
	WZ_SPIN_PID=""
	printf '\r\033[K'
	tput cnorm 2>/dev/null
}

# _wz_run <label> <command...> : run a command in the current shell behind a spinner, output goes to the log
_wz_run() {
	local label="$1" rc
	shift
	if [ "$label" = "metro" ]; then
		_wz_spin_start "${WZ_METRO[@]}"
	else
		_wz_spin_start "$label   " "$label.  " "$label.. " "$label..."
	fi
	printf '\n==== %s: %s\n' "$(date '+%F %T')" "$*" >>"$WIZZARD_LOG"
	"$@" >>"$WIZZARD_LOG" 2>&1
	rc=$?
	_wz_spin_stop
	[ $rc -eq 0 ] || _wz_err "'$1' failed (exit $rc) — see $WIZZARD_LOG"
	return $rc
}

_wz_confirm() {
	local answer
	printf '%s %s(yes/no)%s ' "$1" "$WZ_YELLOW" "$WZ_RESET"
	read -r answer
	case "$answer" in y | Y | yes | Yes | YES) return 0 ;; esac
	return 1
}

# _wz_ask <prompt> <default> : sets WZ_ANSWER, expands a leading ~
_wz_ask() {
	local answer
	printf '%s [%s%s%s]: ' "$1" "$WZ_GREEN" "$2" "$WZ_RESET"
	read -r answer
	answer="${answer:-$2}"
	case "$answer" in "~"*) answer="$HOME${answer#\~}" ;; esac
	WZ_ANSWER="$answer"
}

# big local scratch disk if this machine has one (42 clusters), otherwise ~/.local
_wz_goinfre() {
	local d
	for d in "/goinfre/$USER" "/sgoinfre/$USER" "$HOME/goinfre"; do
		[ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }
	done
	if [ -d /goinfre ] && [ -w /goinfre ] && mkdir -p "/goinfre/$USER" 2>/dev/null; then
		echo "/goinfre/$USER"
		return
	fi
	echo "$HOME/.local"
}

_wz_df() { df -hP "$HOME" 2>/dev/null | awk -v c="$1" 'NR==2 {print $c}'; }

# rc lines are tagged "# 42-wizzard:<tag>" so they can be replaced/removed without touching anything else
_wz_rc_del_in() {
	local tmp
	tmp=$(mktemp) || return 1
	grep -vF -- "$2" "$1" >"$tmp"
	cat "$tmp" >"$1"
	rm -f "$tmp"
}

# _wz_rc_set <tag> <line> : write <line> into ~/.bashrc and ~/.zshrc (empty line = remove) and apply it now
_wz_rc_set() {
	local tag="# 42-wizzard:$1" line="$2" f
	for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
		[ -f "$f" ] || continue
		_wz_rc_del_in "$f" "$tag"
		[ -n "$line" ] && printf '%s %s\n' "$line" "$tag" >>"$f"
	done
	[ -n "$line" ] && eval "$line"
	return 0
}

_wz_local_bin() {
	mkdir -p "$HOME/.local/bin"
	# shellcheck disable=SC2016
	_wz_rc_set localbin 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
}

# remove the contents of each directory, keep the directory itself
_wz_empty() {
	local d
	for d in "$@"; do
		[ -d "$d" ] && find "$d/" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
	done
	return 0
}

_wz_clip() {
	if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
		wl-copy
	elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
		xclip -selection clipboard
	elif [ -n "${DISPLAY:-}" ] && command -v xsel >/dev/null 2>&1; then
		xsel --clipboard --input
	else
		cat >/dev/null
		return 1
	fi
}

_wz_open() { command -v xdg-open >/dev/null 2>&1 && (xdg-open "$1" >/dev/null 2>&1 &); }

_wz_userns_restricted() { [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = "1" ]; }

_wz_multiarch() {
	case "$(uname -m)" in
		x86_64) echo x86_64-linux-gnu ;;
		aarch64) echo aarch64-linux-gnu ;;
		*) echo "$(uname -m)-linux-gnu" ;;
	esac
}

# ───────────────────────────── commands ─────────────────────────────

_wz_clean_targets() {
	_wz_empty \
		"$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info" "$HOME/.local/share/Trash/expunged" \
		"$HOME/.cache" \
		"$HOME/.config/Code/Cache" "$HOME/.config/Code/CachedData" "$HOME/.config/Code/CachedExtensionVSIXs" \
		"$HOME/.config/Code/Code Cache" "$HOME/.config/Code/GPUCache" "$HOME/.config/Code/logs" \
		"$HOME/.config/Code/User/workspaceStorage" \
		"$HOME/.config/Slack/Cache" "$HOME/.config/Slack/Code Cache" "$HOME/.config/Slack/GPUCache" \
		"$HOME/.config/Slack/Service Worker/CacheStorage" \
		"$HOME/.config/discord/Cache" "$HOME/.config/discord/Code Cache" "$HOME/.config/discord/GPUCache" \
		"$HOME/.npm/_cacache" "$HOME/.npm/_logs"
	# Chrome / Chromium / Brave profile caches
	find "$HOME/.config/google-chrome" "$HOME/.config/chromium" "$HOME/.config/BraveSoftware/Brave-Browser" \
		-mindepth 2 -maxdepth 3 -type d \
		\( -path '*/Service Worker/CacheStorage' -o -name 'Application Cache' -o -name GPUCache -o -name 'Code Cache' \) \
		2>/dev/null | while IFS= read -r d; do _wz_empty "$d"; done
	# snap apps (~/snap/<app>/<rev|common>/.cache) and flatpak apps (~/.var/app/<id>/cache)
	find "$HOME/snap" -mindepth 3 -maxdepth 3 -type d -name .cache 2>/dev/null |
		while IFS= read -r d; do _wz_empty "$d"; done
	find "$HOME/.var/app" -mindepth 2 -maxdepth 2 -type d -name cache 2>/dev/null |
		while IFS= read -r d; do _wz_empty "$d"; done
	return 0
}

42-wizzard-clean() {
	printf '• Free storage before cleaning: %s%s%s\n' "$WZ_GREEN" "$(_wz_df 4)" "$WZ_RESET"
	_wz_run cleaning _wz_clean_targets
	printf '• Free storage after cleaning:  %s%s%s\n' "$WZ_GREEN" "$(_wz_df 4)" "$WZ_RESET"
}

42-wizzard-storage() {
	# not "path": in zsh that is tied to $PATH, and overwriting it breaks the user's shell
	local size entry
	printf '• Total storage:     %s%s%s\n' "$WZ_BLUE" "$(_wz_df 2)" "$WZ_RESET"
	printf '• Used storage:      %s%s%s\n' "$WZ_RED" "$(_wz_df 3)" "$WZ_RESET"
	printf '• Available storage: %s%s%s\n' "$WZ_GREEN" "$(_wz_df 4)" "$WZ_RESET"
	if command -v quota >/dev/null 2>&1 && quota -s 2>/dev/null | grep -q .; then
		printf '%sYour quota:%s\n' "$WZ_YELLOW" "$WZ_RESET"
		quota -s 2>/dev/null
	fi
	printf '%sBiggest folders in ~:%s\n' "$WZ_YELLOW" "$WZ_RESET"
	du -xh --max-depth=1 "$HOME" 2>/dev/null | sort -rh | sed -n '2,11p' |
		while IFS=$'\t' read -r size entry; do
			printf '  %s%8s%s  ~%s\n' "$WZ_GREEN" "$size" "$WZ_RESET" "${entry#"$HOME"}"
		done
	printf '%sHeavy files (>50M):%s\n' "$WZ_YELLOW" "$WZ_RESET"
	find "$HOME" -xdev -type f -size +50M -printf '%s\t%p\n' 2>/dev/null | sort -nr | head -n 20 |
		while IFS=$'\t' read -r size entry; do
			printf '  %s%8s%s  ~%s\n' "$WZ_GREEN" "$(numfmt --to=iec "$size")" "$WZ_RESET" "${entry#"$HOME"}"
		done
}

42-wizzard-brew() {
	local dest
	if command -v brew >/dev/null 2>&1; then
		_wz_ok "Homebrew $(brew --version | head -n 1 | awk '{print $2}') is already installed"
		_wz_confirm "Do you want to reinstall it?" || return 0
	fi
	_wz_ask "Where should Homebrew live?" "$(_wz_goinfre)/homebrew"
	dest="$WZ_ANSWER"
	_wz_warn "Outside /home/linuxbrew most formulae build from source (needs git, curl, gcc) — first installs are slow."
	rm -rf "$dest" && mkdir -p "$(dirname "$dest")" || { _wz_err "Cannot write to $dest"; return 1; }
	_wz_run metro sh -c 'git clone --depth=1 https://github.com/Homebrew/brew "$1" ||
		{ mkdir -p "$1" && curl -fsSL https://github.com/Homebrew/brew/tarball/main | tar xz --strip-components 1 -C "$1"; }' _ "$dest" || return 1
	_wz_rc_set brew "eval \"\$(\"$dest/bin/brew\" shellenv)\""
	_wz_run metro brew update --force --quiet || return 1
	_wz_ok "Homebrew v$(brew --version | head -n 1 | awk '{print $2}') installed in $dest"
}

_wz_docker_rootless() { docker info -f '{{json .SecurityOptions}}' 2>/dev/null | grep -q rootless; }

_wz_docker_rootless_ready() {
	local ready=0
	if ! command -v newuidmap >/dev/null 2>&1 || ! command -v newgidmap >/dev/null 2>&1; then
		_wz_err "newuidmap/newgidmap are missing (Ubuntu package 'uidmap')."
		ready=1
	fi
	if ! grep -Eq "^($USER|$(id -u)):" /etc/subuid 2>/dev/null; then
		_wz_err "There is no entry for $USER in /etc/subuid (common with LDAP/network accounts)."
		ready=1
	fi
	if _wz_userns_restricted; then
		_wz_err "AppArmor blocks unprivileged user namespaces (Ubuntu 24.04+), rootlesskit can't start."
		ready=1
	fi
	return $ready
}

# point the rootless daemon's data-root at <dir>, keeping any other daemon.json settings
_wz_docker_data_root() {
	mkdir -p "$1" "$HOME/.config/docker" || return 1
	python3 - "$HOME/.config/docker/daemon.json" "$1" <<'PY'
import json, os, sys
path, root = sys.argv[1], sys.argv[2]
conf = {}
if os.path.exists(path):
    with open(path) as f:
        conf = json.load(f)
conf["data-root"] = root
with open(path, "w") as f:
    json.dump(conf, f, indent=2)
PY
}

42-wizzard-docker() {
	local dest
	if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && ! _wz_docker_rootless; then
		_wz_ok "Docker $(docker version -f '{{.Server.Version}}' 2>/dev/null) is already usable (system daemon)."
		return 0
	fi
	if [ -S /var/run/docker.sock ] && [ ! -w /var/run/docker.sock ]; then
		_wz_warn "A system Docker exists but you're not in the 'docker' group. Staff can fix that with:"
		printf '    sudo usermod -aG docker %s\n' "$USER"
		_wz_warn "Trying a rootless Docker in your own account instead…"
	fi
	if ! _wz_docker_rootless_ready; then
		_wz_err "Rootless Docker can't run on this machine without an admin."
		command -v podman >/dev/null 2>&1 &&
			_wz_warn "podman is installed — try: alias docker=podman"
		return 1
	fi
	_wz_ask "Docker data folder (must be a local disk, not an NFS home)" "$(_wz_goinfre)/docker"
	dest="$WZ_ANSWER"
	_wz_docker_data_root "$dest" || { _wz_err "Cannot write docker config/data folder"; return 1; }
	if [ ! -x "$HOME/bin/dockerd-rootless.sh" ]; then
		_wz_run installing sh -c 'curl -fsSL https://get.docker.com/rootless | FORCE_ROOTLESS_INSTALL=1 sh' || return 1
	fi
	# shellcheck disable=SC2016
	_wz_rc_set dockerpath 'case ":$PATH:" in *":$HOME/bin:"*) ;; *) export PATH="$HOME/bin:$PATH" ;; esac'
	# shellcheck disable=SC2016
	_wz_rc_set dockerhost 'export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"'
	if command -v systemctl >/dev/null 2>&1 && systemctl --user restart docker >>"$WIZZARD_LOG" 2>&1; then
		sleep 2
	else
		_wz_warn "No systemd user session — start the daemon manually with: dockerd-rootless.sh &"
	fi
	if docker info >/dev/null 2>&1; then
		_wz_ok "Rootless Docker $(docker version -f '{{.Server.Version}}' 2>/dev/null) is running, data in $dest"
	else
		_wz_warn "Docker installed but the daemon isn't answering yet — check: systemctl --user status docker"
	fi
}

42-wizzard-code() {
	local dest dir arch c sandbox=""
	_wz_local_bin
	if command -v code >/dev/null 2>&1; then
		_wz_ok "The code command is already available: $(command -v code)"
		return 0
	fi
	for c in /snap/bin/code /usr/share/code/bin/code /usr/bin/code; do
		if [ -x "$c" ]; then
			ln -sf "$c" "$HOME/.local/bin/code"
			_wz_ok "Linked $c → ~/.local/bin/code, you can use the code command now!"
			return 0
		fi
	done
	if command -v flatpak >/dev/null 2>&1 && flatpak info com.visualstudio.code >/dev/null 2>&1; then
		printf '#!/bin/sh\nexec flatpak run com.visualstudio.code "$@"\n' >"$HOME/.local/bin/code"
		chmod +x "$HOME/.local/bin/code"
		_wz_ok "You can use the code command now (flatpak VS Code)!"
		return 0
	fi
	_wz_warn "VS Code isn't installed — installing it in your account."
	_wz_ask "Install folder" "$HOME/.local/opt"
	dest="$WZ_ANSWER"
	case "$(uname -m)" in aarch64) arch=arm64 ;; *) arch=x64 ;; esac
	dir="$dest/VSCode-linux-$arch"
	mkdir -p "$dest" && rm -rf "$dir" || return 1
	_wz_run downloading sh -c 'curl -fsSL "$1" | tar xz -C "$2"' _ \
		"https://update.code.visualstudio.com/latest/linux-$arch/stable" "$dest" || return 1
	# the Chromium sandbox needs a setuid helper or user namespaces; without either, run unsandboxed
	_wz_userns_restricted && sandbox=" --no-sandbox"
	printf '#!/bin/sh\nexec "%s/bin/code"%s "$@"\n' "$dir" "$sandbox" >"$HOME/.local/bin/code"
	chmod +x "$HOME/.local/bin/code"
	mkdir -p "$HOME/.local/share/applications"
	cat >"$HOME/.local/share/applications/code-42-wizzard.desktop" <<EOF
[Desktop Entry]
Name=Visual Studio Code
Exec=$HOME/.local/bin/code %F
Icon=$dir/resources/app/resources/linux/code.png
Type=Application
Categories=Development;IDE;
StartupWMClass=Code
EOF
	_wz_ok "VS Code installed in $dir — you can use the code command now!"
}

42-wizzard-ssh() {
	local key="$HOME/.ssh/id_ed25519" stamp
	mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
	if [ -f "$key" ]; then
		if _wz_confirm "An SSH key already exists ($key). Generate a new one? The old one is kept as a backup."; then
			stamp=$(date +%Y%m%d%H%M%S)
			mv "$key" "$key.bak.$stamp"
			mv "$key.pub" "$key.pub.bak.$stamp" 2>/dev/null
		fi
	fi
	if [ ! -f "$key" ]; then
		ssh-keygen -q -t ed25519 -C "$USER@$(hostname)" -f "$key" -N "" || return 1
		_wz_ok "New key created: $key"
	fi
	if _wz_clip <"$key.pub"; then
		_wz_ok "Public key copied to clipboard"
	else
		_wz_warn "No clipboard tool available, copy this line:"
	fi
	printf '%s%s%s\n' "$WZ_GREEN" "$(cat "$key.pub")" "$WZ_RESET"
	printf '%shttps://profile.intra.42.fr/gitlab_users%s\n' "$WZ_BLUE" "$WZ_RESET"
	_wz_open https://profile.intra.42.fr/gitlab_users
}

42-wizzard-nvm() {
	local tag
	tag=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null |
		sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
	tag="${tag:-v0.40.3}"
	_wz_run installing sh -c 'curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$1/install.sh" | PROFILE=/dev/null bash' _ "$tag" || return 1
	# shellcheck disable=SC2016
	_wz_rc_set nvm 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
	_wz_ok "nvm v$(nvm --version) installed!"
}

42-wizzard-node() {
	# shellcheck disable=SC1091
	command -v nvm >/dev/null 2>&1 || { [ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"; }
	if ! command -v nvm >/dev/null 2>&1; then
		_wz_warn "nvm is not installed, installing nvm first"
		42-wizzard-nvm || return 1
	fi
	_wz_run installing nvm install --lts || return 1
	nvm alias default 'lts/*' >/dev/null 2>&1
	# recent node builds link libatomic, which minimal Ubuntu installs don't ship
	if node --version 2>&1 | grep -q libatomic; then
		_wz_warn "node needs libatomic1, fetching it without sudo"
		42-wizzard-apt libatomic1 >/dev/null
	fi
	if ! node --version >/dev/null 2>&1; then
		_wz_err "node was installed but doesn't start: $(node --version 2>&1 | head -n 1)"
		return 1
	fi
	_wz_ok "node $(node --version) installed!"
	_wz_ok "npm v$(npm --version) installed!"
}

42-wizzard-pip() {
	local pyver url extra="" tmp
	if ! command -v python3 >/dev/null 2>&1; then
		_wz_err "python3 isn't installed"
		return 1
	fi
	if python3 -m pip --version >/dev/null 2>&1; then
		_wz_ok "pip is already installed: $(python3 -m pip --version | awk '{print $1, $2}')"
	else
		pyver=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
		url="https://bootstrap.pypa.io/get-pip.py"
		case "$pyver" in 3.[0-8]) url="https://bootstrap.pypa.io/pip/$pyver/get-pip.py" ;; esac
		# Ubuntu 23.04+ marks the system python as externally managed (PEP 668); --user is still safe
		python3 -c 'import os, sys, sysconfig; sys.exit(not os.path.exists(os.path.join(sysconfig.get_paths()["stdlib"], "EXTERNALLY-MANAGED")))' &&
			extra="--break-system-packages"
		tmp=$(mktemp)
		_wz_run installing sh -c 'curl -fsSL "$1" -o "$2" && python3 "$2" --user $3' _ "$url" "$tmp" "$extra"
		rm -f "$tmp"
	fi
	_wz_local_bin
	_wz_rc_set pip "alias pip='python3 -m pip'"
	if python3 -m pip --version >/dev/null 2>&1; then
		_wz_ok "pip installed! (install packages with: pip install --user <pkg>, or use python3 -m venv)"
	else
		_wz_err "pip not installed — see $WIZZARD_LOG"
		return 1
	fi
}

42-wizzard-oh-my-zsh() {
	if ! command -v zsh >/dev/null 2>&1; then
		_wz_err "zsh isn't installed on this machine and can't be installed without sudo — ask staff."
		return 1
	fi
	if [ -d "$HOME/.oh-my-zsh" ]; then
		_wz_ok "Oh My Zsh is already installed"
	else
		_wz_run installing sh -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' || return 1
		# the installer replaces ~/.zshrc: carry over the wizzard's lines
		[ -f "$HOME/.zshrc.pre-oh-my-zsh" ] &&
			grep -F '# 42-wizzard:' "$HOME/.zshrc.pre-oh-my-zsh" >>"$HOME/.zshrc"
		grep -qF '# 42-wizzard:source' "$HOME/.zshrc" ||
			printf '[ -f "$HOME/.42-wizzard.sh" ] && . "$HOME/.42-wizzard.sh" # 42-wizzard:source\n' >>"$HOME/.zshrc"
		_wz_ok "Oh My Zsh installed!"
	fi
	if [ "$(basename "${SHELL:-}")" != "zsh" ] &&
		_wz_confirm "Your login shell isn't zsh and chsh needs admin rights. Start zsh automatically from bash?"; then
		_wz_rc_del_in "$HOME/.bashrc" "# 42-wizzard:autozsh"
		# shellcheck disable=SC2016
		printf '%s # 42-wizzard:autozsh\n' '[ -t 1 ] && [ -z "${ZSH_VERSION:-}" ] && command -v zsh >/dev/null && exec zsh' >>"$HOME/.bashrc"
		_wz_ok "New terminals will open zsh"
	fi
}

42-wizzard-ds-store() {
	local count excludes
	if _wz_confirm "Remove all .DS_Store files from your home?"; then
		count=$(find "$HOME" -xdev -type f -name .DS_Store -print -delete 2>/dev/null | wc -l)
		_wz_ok "$((count)) .DS_Store files removed"
	else
		_wz_warn "Aborting"
	fi
	# Ubuntu never creates them; the useful part is keeping files copied from Macs out of git
	if _wz_confirm "Ignore .DS_Store in every git repo (global gitignore)?"; then
		excludes=$(git config --global core.excludesFile)
		excludes="${excludes:-$HOME/.gitignore_global}"
		case "$excludes" in "~"*) excludes="$HOME${excludes#\~}" ;; esac
		git config --global core.excludesFile "$excludes"
		grep -qxF .DS_Store "$excludes" 2>/dev/null || echo .DS_Store >>"$excludes"
		_wz_ok ".DS_Store is now ignored by git ($excludes)"
	else
		_wz_warn "Aborting"
	fi
}

42-wizzard-reset() {
	local backup
	if ! command -v dconf >/dev/null 2>&1; then
		_wz_err "dconf not found — only GNOME desktops can be reset"
		return 1
	fi
	_wz_warn "This resets your desktop settings (GNOME: dock, theme, keyboard, shortcuts…). Files are not touched."
	if ! _wz_confirm "${WZ_RED}Are you sure you want to reset your session?${WZ_RESET}"; then
		_wz_warn "Aborting"
		return 0
	fi
	backup="$HOME/.42-wizzard-dconf-backup-$(date +%Y%m%d%H%M%S).ini"
	dconf dump / >"$backup" && _wz_ok "Backup saved: $backup  (restore: dconf load / < $backup)"
	dconf reset -f /
	_wz_ok "Desktop settings reset"
	if _wz_confirm "Log out now so everything reloads?"; then
		gnome-session-quit --logout --no-prompt 2>/dev/null || loginctl terminate-session "${XDG_SESSION_ID:-}"
	fi
}

42-wizzard-apt() {
	local tmp list p failed=0 arch root="$WIZZARD_APT_ROOT"
	if [ $# -eq 0 ]; then
		_wz_err "Usage: 42 -apt <package> [package...]"
		return 1
	fi
	tmp=$(mktemp -d) || return 1
	list="$tmp/packages.txt"
	# the package plus every dependency that isn't already installed on the machine
	apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
		--no-breaks --no-replaces --no-enhances "$@" 2>/dev/null |
		grep -E '^[a-z0-9]' | grep -v ':' | sort -u |
		while IFS= read -r p; do
			dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || echo "$p"
		done >"$list"
	if [ ! -s "$list" ]; then
		_wz_ok "Nothing to do: $* (and its dependencies) already installed or unknown package"
		rm -rf "$tmp"
		return 0
	fi
	printf 'Packages: %s\n' "$(tr '\n' ' ' <"$list")"
	_wz_spin_start "downloading   " "downloading.  " "downloading.. " "downloading..."
	while IFS= read -r p; do
		(cd "$tmp" && apt-get download "$p" >>"$WIZZARD_LOG" 2>&1) || failed=$((failed + 1))
	done <"$list"
	_wz_spin_stop
	[ $failed -eq 0 ] || _wz_warn "$failed package(s) couldn't be downloaded — see $WIZZARD_LOG"
	mkdir -p "$root"
	find "$tmp" -name '*.deb' -exec dpkg -x {} "$root" \; || { rm -rf "$tmp"; return 1; }
	rm -rf "$tmp"
	arch=$(_wz_multiarch)
	_wz_rc_set aptpath "export PATH=\"$root/usr/local/bin:$root/usr/bin:$root/bin:$root/usr/games:\$PATH\""
	_wz_rc_set aptlib "export LD_LIBRARY_PATH=\"$root/usr/lib/$arch:$root/lib/$arch:$root/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
	_wz_rc_set aptman "export MANPATH=\"$root/usr/share/man:\${MANPATH:-}\""
	hash -r 2>/dev/null
	_wz_ok "Installed in $root: $*"
	_wz_warn "Post-install scripts are not run; daemons or packages with hardcoded /usr paths may not work."
}

42-wizzard-update() {
	local tmp
	if [ -n "${WIZZARD_SRC:-}" ] && [ -d "${WIZZARD_SRC:-}/.git" ]; then
		git -C "$WIZZARD_SRC" pull --ff-only || return 1
		cp "$WIZZARD_SRC/42-wizzard.sh" "$WIZZARD_FILE" || return 1
	elif [ -n "${WIZZARD_UPDATE_URL:-}" ]; then
		tmp=$(mktemp)
		curl -fsSL "$WIZZARD_UPDATE_URL" -o "$tmp" && bash -n "$tmp" && mv "$tmp" "$WIZZARD_FILE" ||
			{ rm -f "$tmp"; _wz_err "Update failed"; return 1; }
	else
		_wz_err "No update source: set WIZZARD_SRC (a git clone) or WIZZARD_UPDATE_URL in $WIZZARD_CONF"
		return 1
	fi
	# shellcheck disable=SC1090
	. "$WIZZARD_FILE"
	_wz_ok "42 wizzard is now v$WIZZARD_VERSION"
}

42-wizzard-help() {
	printf '42-wizzard (Ubuntu, no sudo) %sv%s%s\n' "$WZ_GREEN" "$WIZZARD_VERSION" "$WZ_RESET"
	printf '\t%s%-18s%s %s\n' \
		"$WZ_GREEN" "-clean -c" "$WZ_RESET" "Clean your session (trash, caches)." \
		"$WZ_GREEN" "-storage -s" "$WZ_RESET" "Show your storage, biggest folders and heavy files." \
		"$WZ_GREEN" "-code" "$WZ_RESET" "Make the code command work (installs VS Code if needed)." \
		"$WZ_GREEN" "-ssh" "$WZ_RESET" "Generate an SSH key and copy it to your clipboard." \
		"$WZ_GREEN" "-brew" "$WZ_RESET" "Install Homebrew in your account." \
		"$WZ_GREEN" "-docker" "$WZ_RESET" "Set up rootless Docker with its data on goinfre." \
		"$WZ_GREEN" "-nvm" "$WZ_RESET" "Install nvm." \
		"$WZ_GREEN" "-node" "$WZ_RESET" "Install node (LTS) + npm." \
		"$WZ_GREEN" "-pip" "$WZ_RESET" "Install pip for your user." \
		"$WZ_GREEN" "-oh-my-zsh -omz" "$WZ_RESET" "Install oh-my-zsh." \
		"$WZ_GREEN" "-ds-store -ds" "$WZ_RESET" "Remove .DS_Store files, keep them out of git." \
		"$WZ_GREEN" "-apt <pkg...>" "$WZ_RESET" "Install an apt package into ~/.local/apt without sudo." \
		"$WZ_GREEN" "-reset -r" "$WZ_RESET" "Reset your desktop settings." \
		"$WZ_GREEN" "-update -u" "$WZ_RESET" "Update the wizzard." \
		"$WZ_GREEN" "-help -h" "$WZ_RESET" "Show this help."
}

42() {
	local rc
	trap '_wz_spin_stop' INT
	case "$1" in
		-clean | -c) 42-wizzard-clean ;;
		-storage | -s) 42-wizzard-storage ;;
		-reset | -r) 42-wizzard-reset ;;
		-update | -u) 42-wizzard-update ;;
		-brew) 42-wizzard-brew ;;
		-docker) 42-wizzard-docker ;;
		-code) 42-wizzard-code ;;
		-ssh) 42-wizzard-ssh ;;
		-nvm) 42-wizzard-nvm ;;
		-node) 42-wizzard-node ;;
		-pip) 42-wizzard-pip ;;
		-oh-my-zsh | -omz) 42-wizzard-oh-my-zsh ;;
		-ds-store | -ds) 42-wizzard-ds-store ;;
		-apt) shift; 42-wizzard-apt "$@" ;;
		-help | -h | "") 42-wizzard-help ;;
		*)
			_wz_err "42: Unknown flag: $1"
			echo "Usage: 42 -flag"
			42-wizzard-help
			false
			;;
	esac
	rc=$?
	trap - INT
	return $rc
}

# executed directly instead of sourced: run the command
if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
	42 "$@"
	exit $?
elif [ -n "${ZSH_VERSION:-}" ] && [ "${ZSH_EVAL_CONTEXT:-}" = "toplevel" ]; then
	42 "$@"
	exit $?
fi
