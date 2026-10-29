# 42_wizzard for Ubuntu (no sudo)

An Ubuntu port of [0xShady/42_wizzard](https://github.com/0xShady/42_wizzard).
It keeps the same `42 -flag` commands, but everything runs inside your own account:
no `sudo`, no `apt install`, no `chsh`. It works in **bash** (Ubuntu's default) and **zsh**.

## Install

```bash
git clone <this repo> ~/42_wizzard_ubuntu
bash ~/42_wizzard_ubuntu/install.sh
source ~/.42-wizzard.sh      # or open a new terminal
42 -h
```

The installer copies the script to `~/.42-wizzard.sh` and adds one line to `~/.bashrc` (and `~/.zshrc` if you have one).
Every line the wizzard writes to your rc files ends with `# 42-wizzard:<tag>`, so `bash uninstall.sh` can remove them cleanly.

You can also run it without installing: `bash 42-wizzard.sh -s`.

## Commands

| Command | What it does on Ubuntu |
| --- | --- |
| `-clean -c` | Empties Trash, `~/.cache`, VS Code / Slack / Discord / Chrome / Chromium / Brave caches, snap and flatpak app caches, npm cache. Shows free space before/after. |
| `-storage -s` | Total/used/free space of your home, your `quota` if one is set, the 10 biggest folders and the 20 biggest files (>50M). |
| `-code` | Makes `code` work: links an existing VS Code (snap/deb/flatpak), otherwise downloads VS Code into `~/.local/opt` with a `code` launcher in `~/.local/bin` and a menu entry. |
| `-ssh` | Creates an ed25519 key (backs up an existing one instead of deleting `~/.ssh`), copies it with `wl-copy`/`xclip`/`xsel` if available, prints it, and opens the intra GitLab page. |
| `-brew` | Installs Homebrew into goinfre (or `~/.local/homebrew`). |
| `-docker` | Uses system Docker if you can already reach it. Otherwise sets up **rootless Docker** in your account, with its data on goinfre. |
| `-nvm` | Installs the latest nvm. |
| `-node` | Installs Node LTS + npm through nvm (installs nvm first if needed). |
| `-pip` | Installs pip for your user with `get-pip.py --user` and adds `alias pip='python3 -m pip'`. |
| `-oh-my-zsh -omz` | Installs oh-my-zsh without `chsh`, keeps the wizzard's rc lines, and can make bash open zsh automatically. |
| `-ds-store -ds` | Deletes `.DS_Store` files and adds them to your global gitignore. |
| `-apt <pkg…>` | **New.** Downloads a package plus its missing dependencies with `apt-get download` and extracts them into `~/.local/apt`. PATH, LD_LIBRARY_PATH and MANPATH are set for you. Example: `42 -apt jq tree`. |
| `-reset -r` | Backs up and resets your GNOME settings (`dconf`), then offers to log out. Your files are not touched. |
| `-update -u` | `git pull`s the clone you installed from and reinstalls it. |
| `-help -h` | Help. |

Output from long-running steps goes to `/tmp/42-wizzard-$USER.log`. When something fails, the error message points to that file.

## What's different from the macOS version, and why

- **Paths**: `~/Library/Caches` → `~/.cache`, `~/.Trash` → `~/.local/share/Trash`, `~/Library/Application Support/X` → `~/.config/X`.
- **`pbcopy` / `open` / `osascript` / `defaults`** → `wl-copy`/`xclip`/`xsel`, `xdg-open`, `gnome-session-quit`, `dconf`.
- **`-reset`**: 42's macOS reset wipes the whole session at the next login. Ubuntu has no equivalent you can trigger without root, so this resets your desktop settings only. A backup is saved, and you restore it with `dconf load / < backup.ini`.
- **`-ds-store`**: Linux never creates `.DS_Store`, so "prevent" means keeping them out of git.
- **`-ssh`** no longer runs `rm -rf ~/.ssh`. That would have deleted your other keys and `known_hosts`.
- **The updater no longer runs on every new shell.** The original downloaded the script from GitHub each time a terminal opened.

## Limits without sudo (read this before `-docker` / `-apt`)

- **Docker**: if Docker is installed system-wide but you get `permission denied` on `/var/run/docker.sock`, you're not in the `docker` group, and only an admin can add you (`sudo usermod -aG docker $USER`). Rootless Docker needs three things only an admin can provide:
  the `uidmap` package (`newuidmap`), an entry for you in `/etc/subuid`, and, on Ubuntu 24.04+, permission for unprivileged user namespaces in AppArmor.
  `42 -docker` checks all three and tells you exactly which one is missing. If `podman` is installed, it suggests that instead.
  The Docker data has to live on a local disk (goinfre). Rootless Docker doesn't work on NFS homes.
- **`-apt`**: uses the machine's existing package index (you can't run `apt update` without root) and doesn't run post-install scripts. That's fine for CLI tools and libraries, but not for daemons, or for programs that look for their own files under `/usr`. zsh is one example, so `-apt zsh` won't give you a working zsh.
- **Homebrew**: outside `/home/linuxbrew/.linuxbrew`, most formulae are built from source. That works, but it is slow and needs `gcc`, `git` and `curl` on the machine.
- **VS Code**: on Ubuntu 24.04+, the downloaded VS Code can't use Chromium's sandbox without root, so the launcher adds `--no-sandbox` automatically.
- **`-clean`** empties all of `~/.cache`. That is safe by design, but things cached there (pip wheels, Playwright browsers, Hugging Face models…) will be downloaded again the next time you need them.
