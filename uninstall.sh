#!/usr/bin/env bash
# Removes 42-wizzard and every line it added to ~/.bashrc / ~/.zshrc.
# Things it installed (brew, nvm, VS Code, ~/.local/apt…) are left in place.

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
	[ -f "$rc" ] || continue
	tmp=$(mktemp)
	grep -vF '# 42-wizzard:' "$rc" >"$tmp"
	cat "$tmp" >"$rc"
	rm -f "$tmp"
done
rm -f "$HOME/.42-wizzard.sh" "$HOME/.42-wizzard.conf"
echo "42 wizzard removed — open a new terminal."
