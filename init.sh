#!/usr/bin/env bash
# Bootstrap a machine for GitHub user daniel-baez.
#
#   curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash
#
# Installs the GitHub CLI, signs in as daniel-baez, clones daniel-baez/dotfiles
# with that login, and runs the dotfiles installer. Safe to run again.
# Interactive prompts read /dev/tty so this works when piped from curl.

if [ -z "${BASH_VERSION:-}" ]; then
  printf 'error: init.sh requires bash\n' >&2
  exit 1
fi

set -euo pipefail

EXPECTED_USER="daniel-baez"
DOTFILES_REPO="daniel-baez/dotfiles"
DOTFILES_HTTPS="https://github.com/daniel-baez/dotfiles.git"
GH_APT_KEY_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"
GH_APT_REPO="https://cli.github.com/packages"
GH_RPM_REPO="https://cli.github.com/packages/rpm/gh-cli.repo"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# Test seams. Leave these unset. They are honored only when INIT_TEST_MODE=1
# so a stray environment variable cannot point a real install at a fixture.
#   INIT_OS_RELEASE, INIT_UNAME_S, INIT_UNAME_M, INIT_DPKG_ARCH, INIT_DEVICE_TREE_MODEL

usage() {
  cat <<EOF
Usage: init.sh [arguments for ~/workspace/dotfiles/install.sh]

  curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash

With no arguments, the dotfiles installer runs as:

  ./install.sh --all --non-interactive

On Fedora GNOME, --all is the full install: shell, bins, git, tools,
keyboard, and the GNOME desktop settings. --non-interactive is the
installer's entry point for other setup scripts, so a piped run does
not ask which modules to install.

Any other arguments replace that default and are forwarded unchanged:

  curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash -s -- --dry-run
  curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash -s -- shell git

-h, --help    Show this help and do not change the machine.

Supported systems:
  Debian 13 (trixie) and Raspberry Pi OS Trixie, arm64 and amd64
  Fedora (dnf)
  macOS (Homebrew)
EOF
}

step() {
  printf '\n==> %s\n' "$1"
}

say() {
  printf '    %s\n' "$1"
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

supported_systems_text() {
  cat <<'EOF'
Supported systems:
  - Debian 13 (trixie) and Raspberry Pi OS Trixie, arm64 and amd64, via GitHub's apt repository
  - Fedora, via dnf and GitHub's rpm repository
  - macOS, via Homebrew
EOF
}

die_unsupported() {
  printf 'error: %s\n\n' "$1" >&2
  supported_systems_text >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

test_mode() {
  [[ "${INIT_TEST_MODE:-}" == "1" ]]
}

uname_s() {
  if test_mode && [[ -n "${INIT_UNAME_S+x}" ]]; then
    printf '%s' "$INIT_UNAME_S"
  else
    uname -s
  fi
}

uname_m() {
  if test_mode && [[ -n "${INIT_UNAME_M+x}" ]]; then
    printf '%s' "$INIT_UNAME_M"
  else
    uname -m
  fi
}

os_release_path() {
  if test_mode && [[ -n "${INIT_OS_RELEASE+x}" ]]; then
    printf '%s' "$INIT_OS_RELEASE"
  else
    printf '%s' /etc/os-release
  fi
}

debian_arch() {
  local arch
  if test_mode && [[ -n "${INIT_DPKG_ARCH+x}" ]]; then
    printf '%s' "$INIT_DPKG_ARCH"
    return 0
  fi
  if ! have dpkg; then
    die "dpkg is required to detect the Debian architecture"
  fi
  arch="$(dpkg --print-architecture)"
  printf '%s' "$arch"
}

os_release_value() {
  local key="$1" file="$2" line val
  [[ -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '' | \#*) continue ;;
    esac
    case "$line" in
      "$key"=*)
        val="${line#"$key"=}"
        case "$val" in
          \"*\")
            val="${val#\"}"
            val="${val%\"}"
            ;;
          \'*\')
            val="${val#\'}"
            val="${val%\'}"
            ;;
        esac
        printf '%s' "$val"
        return 0
        ;;
    esac
  done < "$file"
  return 1
}

load_os_release() {
  local file
  file="$(os_release_path)"
  if [[ ! -f "$file" ]]; then
    die_unsupported "unsupported Linux ($(uname_m)): ${file} was not found."
  fi
  OS_ID="$(os_release_value ID "$file" || true)"
  OS_VERSION_ID="$(os_release_value VERSION_ID "$file" || true)"
  OS_CODENAME="$(os_release_value VERSION_CODENAME "$file" || true)"
  OS_VERSION="$(os_release_value VERSION "$file" || true)"
  OS_PRETTY="$(os_release_value PRETTY_NAME "$file" || true)"
  OS_VARIANT_ID="$(os_release_value VARIANT_ID "$file" || true)"
  if [[ -z "$OS_PRETTY" ]]; then
    OS_PRETTY="${OS_ID:-Linux}"
  fi
  OS_PRETTY="${OS_PRETTY} ($(uname_m))"
}

is_debian_id() {
  case "${OS_ID:-}" in
    debian | raspbian | raspi | rpios) return 0 ;;
    *) return 1 ;;
  esac
}

is_trixie() {
  if [[ "${OS_CODENAME:-}" == "trixie" || "${OS_VERSION_ID:-}" == "13" ]]; then
    return 0
  fi
  case "${OS_VERSION:-}" in
    *trixie*) return 0 ;;
  esac
  return 1
}

is_raspberry_pi() {
  local file model
  if test_mode && [[ -n "${INIT_DEVICE_TREE_MODEL+x}" ]]; then
    file="$INIT_DEVICE_TREE_MODEL"
  else
    file="/proc/device-tree/model"
  fi
  [[ -f "$file" ]] || return 1
  model="$(tr -d '\000' < "$file" 2>/dev/null || true)"
  [[ "$model" == *"Raspberry Pi"* ]]
}

assert_debian_arch() {
  local arch
  arch="$(debian_arch)"
  case "$arch" in
    amd64 | arm64)
      OS_ARCH="$arch"
      ;;
    *)
      die_unsupported "unsupported architecture ${arch} on ${OS_PRETTY}. Debian and Raspberry Pi OS need arm64 or amd64."
      ;;
  esac
}

detect_os() {
  local kernel
  kernel="$(uname_s)"
  OS_ID=""
  OS_VERSION_ID=""
  OS_CODENAME=""
  OS_VERSION=""
  OS_PRETTY=""
  OS_VARIANT_ID=""
  OS_ARCH=""
  OS_KIND=""
  case "$kernel" in
    Darwin)
      OS_KIND="macos"
      OS_ID="macos"
      OS_PRETTY="macOS ($(uname_m))"
      return 0
      ;;
    Linux) ;;
    *)
      die_unsupported "unsupported operating system: ${kernel} ($(uname_m))."
      ;;
  esac

  load_os_release
  if [[ "$OS_ID" == "fedora" ]]; then
    OS_KIND="fedora"
    return 0
  fi
  if is_debian_id; then
    if ! is_trixie; then
      die_unsupported "found ${OS_PRETTY}. Only Debian 13 (trixie) and Raspberry Pi OS Trixie are supported, on arm64 and amd64."
    fi
    OS_KIND="debian"
    assert_debian_arch
    return 0
  fi
  die_unsupported "unsupported operating system: ${OS_PRETTY}."
}

is_gnome_session() {
  local desk
  desk="$(printf '%s' "${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$desk" == *gnome* ]]
}

# /dev/tty is mode 0666 even when this process has no controlling terminal.
# Opening it is the check that distinguishes a real session from CI.
tty_available() {
  ( : </dev/tty >/dev/tty ) 2>/dev/null
}

require_tty() {
  if tty_available; then
    return 0
  fi
  die "need a terminal for ${1}. A piped install works from a local terminal: curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash"
}

prompt_yes() {
  local prompt="$1" reply
  require_tty "a yes/no question"
  printf '%s' "$prompt" >/dev/tty
  IFS= read -r reply </dev/tty || reply=""
  case "$reply" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# sudo only for system package commands. Root runs them directly.
# Password prompts and apt/dnf questions read the terminal, not the curl pipe.
run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    if "$@"; then
      return 0
    fi
    die "command failed: $*"
  fi
  if ! have sudo; then
    die "sudo is required to run: $*"
  fi
  if tty_available; then
    # The package command must read the terminal. sudo's own password
    # prompt already uses /dev/tty; this redirect is for apt and dnf.
    # shellcheck disable=SC2024
    if sudo "$@" </dev/tty; then
      return 0
    fi
  else
    if sudo -n "$@"; then
      return 0
    fi
    die "sudo needs a password and there is no terminal. Re-run init.sh from a terminal."
  fi
  die "command failed: $*"
}

gh_works() {
  have gh || return 1
  gh --version >/dev/null 2>&1
}

gh_version_line() {
  local ver
  ver="$(gh --version)" || die "gh is on PATH but 'gh --version' failed"
  printf '%s\n' "${ver%%$'\n'*}"
}

install_gh_debian() {
  local arch key list
  arch="$(debian_arch)"
  case "$arch" in
    amd64 | arm64) ;;
    *)
      die_unsupported "unsupported architecture ${arch}. Debian and Raspberry Pi OS need arm64 or amd64."
      ;;
  esac

  # Same repository the GitHub CLI documents for Debian and Raspberry Pi OS:
  # https://github.com/cli/cli/blob/trunk/docs/install_linux.md
  say "installing GitHub CLI from ${GH_APT_REPO} (apt, ${arch})"
  # Slim images have neither wget nor the CA bundle the key download needs.
  if ! have wget || ! dpkg -s ca-certificates >/dev/null 2>&1; then
    say "installing wget and ca-certificates"
    run_root env DEBIAN_FRONTEND=noninteractive apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y wget ca-certificates
  fi

  key="$(mktemp)"
  list="$(mktemp)"
  if ! wget -nv -O "$key" "$GH_APT_KEY_URL"; then
    rm -f "$key" "$list"
    die "failed to download the GitHub CLI apt signing key"
  fi
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] %s stable main\n' \
    "$arch" "$GH_APT_REPO" >"$list"
  run_root mkdir -p -m 755 /etc/apt/keyrings
  run_root tee /etc/apt/keyrings/githubcli-archive-keyring.gpg <"$key" >/dev/null
  run_root chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  run_root mkdir -p -m 755 /etc/apt/sources.list.d
  run_root tee /etc/apt/sources.list.d/github-cli.list <"$list" >/dev/null
  rm -f "$key" "$list"
  run_root env DEBIAN_FRONTEND=noninteractive apt-get update
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y gh
}

dnf_major_is_5() {
  local ver first
  ver="$(dnf --version)" || die "could not run dnf --version"
  first="${ver%%$'\n'*}"
  case "$first" in
    dnf5* | 5.* | *dnf5*) return 0 ;;
    *) return 1 ;;
  esac
}

install_gh_fedora() {
  if ! have dnf; then
    die "Fedora was detected but dnf is not installed"
  fi
  say "installing GitHub CLI from ${GH_RPM_REPO} (dnf)"
  if [[ ! -f /etc/yum.repos.d/gh-cli.repo ]]; then
    if dnf_major_is_5; then
      run_root dnf install -y dnf5-plugins
      run_root dnf config-manager addrepo --from-repofile="$GH_RPM_REPO"
    else
      run_root dnf install -y 'dnf-command(config-manager)'
      run_root dnf config-manager --add-repo "$GH_RPM_REPO"
    fi
  else
    say "GitHub CLI dnf repository is already configured"
  fi
  run_root dnf install -y gh
}

load_brew_from_disk() {
  local candidate
  if have brew; then
    return 0
  fi
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      # Official Homebrew setup. shellenv prints export statements.
      # shellcheck disable=SC2294
      eval "$("$candidate" shellenv)"
      hash -r
      return 0
    fi
  done
  return 1
}

install_homebrew() {
  local installer
  if [[ "$(id -u)" -eq 0 ]]; then
    die "on macOS, run init.sh as your user so Homebrew is not installed as root"
  fi
  require_tty "the Homebrew installer"
  if ! have curl; then
    die "curl is required to download the Homebrew installer"
  fi
  say "Homebrew is not installed; running the official installer"
  installer="$(mktemp)"
  if ! curl -fsSL "$HOMEBREW_INSTALL_URL" -o "$installer"; then
    rm -f "$installer"
    die "failed to download the Homebrew installer"
  fi
  if ! /bin/bash "$installer" </dev/tty; then
    rm -f "$installer"
    die "the Homebrew installer failed"
  fi
  rm -f "$installer"
  hash -r
  if ! load_brew_from_disk; then
    die "Homebrew finished installing but brew is not on PATH"
  fi
}

install_gh_macos() {
  if [[ "$(id -u)" -eq 0 ]]; then
    die "on macOS, run init.sh as your user so Homebrew is not installed as root"
  fi
  if ! load_brew_from_disk; then
    install_homebrew
  fi
  say "installing GitHub CLI with Homebrew"
  brew install gh
}

install_github_cli() {
  if gh_works; then
    say "already installed: $(gh_version_line)"
    return 0
  fi
  case "$OS_KIND" in
    debian) install_gh_debian ;;
    fedora) install_gh_fedora ;;
    macos) install_gh_macos ;;
    *) die "no GitHub CLI install method for this system" ;;
  esac
  hash -r
  if ! gh_works; then
    die "GitHub CLI install finished but 'gh --version' failed"
  fi
  say "installed: $(gh_version_line)"
}

reject_token_env() {
  if [[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]]; then
    die "GH_TOKEN or GITHUB_TOKEN is set. Those variables override 'gh auth login', so this script cannot check that the signed-in user is ${EXPECTED_USER}. Unset them and rerun."
  fi
}

gh_login() {
  require_tty "GitHub login"
  say "starting gh auth login (web / device flow, HTTPS)"
  say "if no browser opens, finish the one-time code at https://github.com/login/device"
  if ! gh auth login --hostname github.com --git-protocol https --web </dev/tty; then
    die "GitHub login did not finish. Rerun init.sh to try the browser flow again."
  fi
}

current_login() {
  local login
  if ! login="$(gh api user --jq .login)"; then
    die "could not read the signed-in user with: gh api user --jq .login"
  fi
  if [[ -z "$login" ]]; then
    die "gh api user --jq .login returned an empty login"
  fi
  printf '%s' "$login"
}

configure_git_for_gh() {
  say "setting the gh git protocol to HTTPS"
  gh config set git_protocol https --host github.com
  say "configuring git to use gh as the credential helper"
  gh auth setup-git --hostname github.com
}

ensure_expected_user() {
  local login
  login="$(current_login)"
  if [[ "$login" == "$EXPECTED_USER" ]]; then
    say "authenticated as ${login}"
    return 0
  fi
  printf 'error: authenticated as %s, expected %s.\n' "$login" "$EXPECTED_USER" >&2
  if ! tty_available; then
    die "refusing to continue as ${login}. From a terminal, rerun init.sh and accept the prompt to log out and sign in as ${EXPECTED_USER}. Or run: gh auth logout --hostname github.com --user ${login}"
  fi
  if prompt_yes "Log out of ${login} and sign in again as ${EXPECTED_USER}? [y/N] "; then
    say "logging out ${login}"
    if ! gh auth logout --hostname github.com --user "$login" </dev/tty; then
      die "gh auth logout failed for ${login}"
    fi
    gh_login
    login="$(current_login)"
    if [[ "$login" != "$EXPECTED_USER" ]]; then
      die "still authenticated as ${login}, not ${EXPECTED_USER}. Sign in as ${EXPECTED_USER} and rerun init.sh."
    fi
    say "authenticated as ${login}"
    return 0
  fi
  die "stopped. This bootstrap is for ${EXPECTED_USER} only. Log out (gh auth logout --hostname github.com --user ${login}) and rerun init.sh."
}

ensure_auth() {
  reject_token_env
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    say "GitHub CLI is already logged in; skipping gh auth login"
  else
    gh_login
  fi
  ensure_expected_user
  configure_git_for_gh
}

ensure_workspace() {
  local dir="${HOME}/workspace"
  if [[ -d "$dir" ]]; then
    say "already exists: ${dir}"
  else
    mkdir -p "$dir"
    say "created ${dir}"
  fi
}

ensure_git() {
  if have git && git --version >/dev/null 2>&1; then
    say "git is already installed"
    return 0
  fi
  say "installing git"
  case "$OS_KIND" in
    debian)
      run_root env DEBIAN_FRONTEND=noninteractive apt-get update
      run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates
      ;;
    fedora)
      run_root dnf install -y git ca-certificates
      ;;
    macos)
      if ! load_brew_from_disk; then
        die "git is missing and Homebrew is not available to install it"
      fi
      brew install git
      ;;
    *)
      die "do not know how to install git on this system"
      ;;
  esac
  if ! have git; then
    die "git install finished but git is not on PATH"
  fi
}

remote_is_dotfiles() {
  local url="$1"
  url="${url%.git}"
  url="${url%/}"
  case "$url" in
    https://github.com/daniel-baez/dotfiles) return 0 ;;
    git@github.com:daniel-baez/dotfiles) return 0 ;;
    ssh://git@github.com/daniel-baez/dotfiles) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_dotfiles_checkout() {
  local dest="${HOME}/workspace/dotfiles" url
  if [[ -e "$dest" && ! -d "$dest" ]]; then
    die "${dest} exists and is not a directory. Move it aside and rerun init.sh."
  fi
  if [[ -e "$dest/.git" ]]; then
    if ! url="$(git -C "$dest" remote get-url origin)"; then
      die "could not read origin in ${dest}"
    fi
    if ! remote_is_dotfiles "$url"; then
      die "origin of ${dest} is '${url}', not ${DOTFILES_REPO}. Refusing to pull."
    fi
    case "$url" in
      https://github.com/daniel-baez/dotfiles | https://github.com/daniel-baez/dotfiles.git) ;;
      *)
        say "setting origin to ${DOTFILES_HTTPS} so git uses gh credentials"
        git -C "$dest" remote set-url origin "$DOTFILES_HTTPS"
        ;;
    esac
    say "updating ${dest} (git pull --ff-only)"
    if ! GIT_TERMINAL_PROMPT=0 git -C "$dest" pull --ff-only; then
      die "git pull --ff-only failed in ${dest}. Keep the local commits, then rerun init.sh after the branch can fast-forward."
    fi
    return 0
  fi
  if [[ -e "$dest" ]]; then
    die "${dest} exists but is not a git clone. Move it aside and rerun init.sh."
  fi
  say "cloning ${DOTFILES_REPO} into ${dest}"
  # The https:// URL forces the protocol. gh auth setup-git supplies the token,
  # including after the repository becomes private.
  if ! GIT_TERMINAL_PROMPT=0 gh repo clone "$DOTFILES_HTTPS" "$dest"; then
    die "gh repo clone failed for ${DOTFILES_REPO}. Confirm the login can read that repository and rerun init.sh."
  fi
}

format_args() {
  local out="" arg
  for arg in "$@"; do
    printf -v out '%s %q' "$out" "$arg"
  done
  printf '%s' "${out# }"
}

run_dotfiles_installer() {
  local dest="${HOME}/workspace/dotfiles"
  local script="${dest}/install.sh"
  local rc=0
  if [[ ! -f "$script" ]]; then
    die "dotfiles installer not found at ${script}"
  fi
  chmod +x "$script"
  if [[ $# -eq 0 ]]; then
    # --all is the full dotfiles install. On Fedora GNOME that includes
    # desktop settings (flat mouse, screenshot shortcuts, us+altgr-intl).
    # --non-interactive is the entry point other setup scripts should call:
    # same modules, and install.sh does not read stdin.
    set -- --all --non-interactive
    if [[ "${OS_ID:-}" == "fedora" ]] && is_gnome_session; then
      say "Fedora GNOME: ./install.sh $(format_args "$@")"
    elif [[ "${OS_ID:-}" == "fedora" && "${OS_VARIANT_ID:-}" == "workstation" ]]; then
      say "Fedora Workstation: ./install.sh $(format_args "$@")"
    else
      say "running ./install.sh $(format_args "$@")"
    fi
  else
    say "forwarding arguments to install.sh: $(format_args "$@")"
  fi
  if tty_available; then
    (cd "$dest" && ./install.sh "$@") </dev/tty || rc=$?
  else
    (cd "$dest" && ./install.sh "$@") || rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    die "dotfiles installer failed (exit ${rc}). Fix the error above and rerun init.sh. Repeating it is safe."
  fi
}

refuse_root_sudo() {
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    die "run init.sh as ${SUDO_USER}, not through sudo. The script asks for sudo only when a package install needs it."
  fi
}

main() {
  if [[ $# -eq 1 && ("$1" == "-h" || "$1" == "--help") ]]; then
    usage
    exit 0
  fi
  if [[ -z "${HOME:-}" || ! -d "$HOME" || ! -w "$HOME" ]]; then
    die "HOME must be a writable directory"
  fi
  refuse_root_sudo
  # apt must not stop on a debconf prompt when stdin is the curl pipe.
  export DEBIAN_FRONTEND=noninteractive
  detect_os
  printf 'Bootstrap for GitHub user %s\n' "$EXPECTED_USER"
  printf 'System: %s\n' "$OS_PRETTY"
  if [[ "$OS_KIND" == "debian" ]]; then
    say "apt architecture: ${OS_ARCH}"
  fi
  if is_raspberry_pi; then
    say "Raspberry Pi hardware detected"
  fi

  step "1/5  Install GitHub CLI (gh)"
  install_github_cli

  step "2/5  Log in with gh"
  ensure_auth

  step "3/5  Create workspace"
  ensure_workspace

  step "4/5  Clone dotfiles"
  ensure_git
  ensure_dotfiles_checkout

  step "5/5  Run dotfiles installer"
  run_dotfiles_installer "$@"

  printf '\nDone. Dotfiles are installed for %s.\n' "$EXPECTED_USER"
  printf 'Open a new shell, or run: source ~/.dotfiles.bashrc\n'
}

# Execute on `bash init.sh` and on `curl | bash`. Do not execute when sourced.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
