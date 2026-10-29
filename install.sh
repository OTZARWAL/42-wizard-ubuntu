#!/usr/bin/env bash
# Installs 42-wizzard for the current user only (no sudo):
#   copies 42-wizzard.sh to ~/.42-wizzard.sh and sources it from ~/.bashrc and ~/.zshrc.
# Usage: bash install.sh        (from a clone of this folder)

set -e
SRC_DIR=$(cd "$(dirname "$0")" && pwd)
TAG="# 42-wizzard:source"
LINE='[ -f "$HOME/.42-wizzard.sh" ] && . "$HOME/.42-wizzard.sh"'

if [ ! -f "$SRC_DIR/42-wizzard.sh" ]; then
	echo "42-wizzard.sh not found next to install.sh" >&2
	exit 1
fi

cp "$SRC_DIR/42-wizzard.sh" "$HOME/.42-wizzard.sh"
chmod +x "$HOME/.42-wizzard.sh"
# remembered so "42 -update" can pull from this clone
printf 'WIZZARD_SRC=%q\n' "$SRC_DIR" >"$HOME/.42-wizzard.conf"

touch "$HOME/.bashrc"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
	[ -f "$rc" ] || continue
	grep -qF "$TAG" "$rc" || printf '%s %s\n' "$LINE" "$TAG" >>"$rc"
done

VERSION=$(sed -n 's/^WIZZARD_VERSION="\(.*\)"/\1/p' "$HOME/.42-wizzard.sh")
printf '42 wizzard \033[1;32mv%s\033[0m installed\n' "$VERSION"
printf 'open a new terminal (or run: source ~/.42-wizzard.sh), then \033[1;32m42 -h\033[0m\n'
