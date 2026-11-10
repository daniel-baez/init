# init

One command to set up a machine for GitHub user `daniel-baez`.

```bash
curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash
```

The script reads prompts from the terminal, so piping it from `curl` is safe. Run it in a terminal the first time: GitHub login needs a browser or the device code at <https://github.com/login/device>.

## What it does

1. Detects the OS and stops if it is not one of the systems below.
2. Installs the GitHub CLI (`gh`) when `gh --version` does not already succeed.
   - Debian and Raspberry Pi OS Trixie: GitHub's apt repository.
   - Fedora: GitHub's rpm repository via `dnf` (dnf5 or dnf4).
   - macOS: Homebrew, installing Homebrew first when `brew` is missing.
3. Runs `gh auth login` with the web / device flow and HTTPS as the git protocol, then `gh auth setup-git`. Skips `gh auth login` when `gh auth status` already shows a github.com login. Checks `gh api user --jq .login`. If that is not `daniel-baez`, it stops and asks whether to log out and sign in again.
4. Creates `$HOME/workspace` when it is missing.
5. Clones `daniel-baez/dotfiles` into `$HOME/workspace/dotfiles` with `gh repo clone` over HTTPS, so a private repository still uses the `gh` login. When the checkout is already there, it runs `git pull --ff-only`.
6. Runs `~/workspace/dotfiles/install.sh`. With no extra arguments that is:

   ```bash
   ./install.sh --all --non-interactive
   ```

   `--all` installs every dotfiles module. On Fedora GNOME that includes the desktop settings (flat mouse, screenshot shortcuts, and the `us+altgr-intl` input source). `--non-interactive` is the installer's entry point for other setup scripts: the same modules, without asking which ones to install.

   Arguments after the script are forwarded to `install.sh` and replace that default:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash -s -- --dry-run
   curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash -s -- shell git
   ```

   `init.sh --help` prints usage and does not change the machine. Every other argument is forwarded.

`sudo` is used only for apt and dnf package installs. On macOS the Homebrew installer asks for its own password when it needs one. The dotfiles installer may ask for `sudo` again for its own packages. Nothing in this repository is a token or a password. `gh` stores the login on the machine.

`GH_TOKEN` and `GITHUB_TOKEN` override `gh auth login`. The script stops when either is set, so the account check cannot be pointed at a different token by accident. Unset them and run the command again.

## Supported systems

| System | Architectures | How `gh` is installed |
| --- | --- | --- |
| Debian 13 (trixie) | `amd64`, `arm64` | GitHub apt repository |
| Raspberry Pi OS Trixie | `amd64`, `arm64` | GitHub apt repository |
| Fedora | the architectures `dnf` supports | GitHub rpm repository |
| macOS | Apple Silicon and Intel | Homebrew |

Anything else stops before it changes the machine, including older Debian and Raspberry Pi OS releases, 32-bit `armhf`, and Ubuntu. Run the script as your user. If it needs a package, it asks `sudo` itself. `sudo bash init.sh` is refused when `SUDO_USER` is set, so dotfiles are not installed into `/root`.

## Running it again

The script is meant to be run more than once.

- An existing `gh` is left as it is. It is not upgraded.
- A github.com login that is already `daniel-baez` does not open the browser again. HTTPS and `gh auth setup-git` are applied on every run, so a later `git pull` of a private dotfiles repo still goes through `gh`.
- `$HOME/workspace` is created only when it is missing.
- An existing `$HOME/workspace/dotfiles` checkout is updated with `git pull --ff-only`. Local commits that are not on the remote are left in place, and the script stops so you can reconcile them. The directory is never deleted. An SSH origin for this same repository is switched to HTTPS so the pull uses the `gh` credential helper.
- A path that already exists and is not that git checkout is left untouched, and the script stops.
- The dotfiles installer is safe to repeat: it keeps existing symlinks, does not duplicate shell snippets, and installs packages that are already present again.

`git pull --ff-only` refuses to merge. Finish or move the local commits, then run the same curl command again.

## Tests

```bash
bash tests/test_init.sh
shellcheck init.sh tests/test_init.sh tests/container_gh.sh
```

`tests/container_gh.sh` installs real `gh` in a Debian Trixie container and a Fedora container, checks that a second run skips the install, and checks that an unsupported Debian release stops before installing anything. GitHub login stays interactive, so that step is covered with a fake `gh` in `tests/test_init.sh`.
