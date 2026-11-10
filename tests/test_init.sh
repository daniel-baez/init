#!/usr/bin/env bash
# Unit tests for init.sh. They stub gh, git, and sudo so nothing is installed
# and no network call is made. GitHub login is driven through a pty.
# SC2317 (0.9) and SC2329 (0.11) flag stubs that override commands after source.
# shellcheck disable=SC2016,SC2317,SC2329,SC1091,SC2030,SC2031
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"

INIT_OUT=""
INIT_STATUS=0
HOME=""
GH_LOG=""
GIT_LOG=""
SUDO_LOG=""
INSTALL_ARGS_FILE=""
INIT_UNAME_S="Linux"
INIT_UNAME_M="x86_64"
INIT_OS_RELEASE=""
INIT_DPKG_ARCH=""
GH_STATUS_EXIT=0
GH_LOGIN="daniel-baez"
GH_LOGIN_SEQUENCE_FILE=""
GIT_ORIGIN_URL="https://github.com/daniel-baez/dotfiles.git"
GIT_PULL_EXIT=0
INSTALL_EXIT=0
XDG_CURRENT_DESKTOP=""
DESKTOP_SESSION=""
WITH_GH_TOKEN=""
WITH_GITHUB_TOKEN=""

write_stub() {
  local name="$1"
  shift
  printf '%s\n' "#!/usr/bin/env bash" >"$STUB_BIN/$name"
  printf '%s\n' "$@" >>"$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
}

write_stub gh \
  'set -euo pipefail' \
  'log="${GH_LOG:?}"' \
  'printf "gh" >> "$log"' \
  'if [[ $# -gt 0 ]]; then printf " %q" "$@" >> "$log"; fi' \
  'printf "\n" >> "$log"' \
  'case "${1:-}" in' \
  '  --version) printf "%s\n" "gh version 9.9.9 (test)" ;;' \
  '  auth)' \
  '    case "${2:-}" in' \
  '      status) exit "${GH_STATUS_EXIT:-0}" ;;' \
  '      login|logout|setup-git) ;;' \
  '      *) printf "unexpected gh %s\n" "$*" >&2; exit 99 ;;' \
  '    esac' \
  '    ;;' \
  '  api)' \
  '    if [[ -n "${GH_LOGIN_SEQUENCE_FILE:-}" ]]; then' \
  '      login="$(sed -n "1p" "$GH_LOGIN_SEQUENCE_FILE")"' \
  '      sed -i "1d" "$GH_LOGIN_SEQUENCE_FILE"' \
  '      printf "%s\n" "$login"' \
  '    else' \
  '      printf "%s\n" "${GH_LOGIN:-daniel-baez}"' \
  '    fi' \
  '    ;;' \
  '  config) ;;' \
  '  repo)' \
  '    if [[ "${2:-}" != "clone" ]]; then printf "unexpected gh %s\n" "$*" >&2; exit 99; fi' \
  '    dest="${4:?clone destination missing}"' \
  '    mkdir -p "$dest/.git"' \
  '    cat > "$dest/install.sh" <<EOF' \
  '#!/usr/bin/env bash' \
  'printf "%s\\n" "\$@" > "\${INSTALL_ARGS_FILE:?}"' \
  'exit "\${INSTALL_EXIT:-0}"' \
  'EOF' \
  '    chmod +x "$dest/install.sh"' \
  '    ;;' \
  '  *) printf "unexpected gh %s\n" "$*" >&2; exit 99 ;;' \
  'esac'

write_stub git \
  'set -euo pipefail' \
  'log="${GIT_LOG:?}"' \
  'printf "git" >> "$log"' \
  'if [[ $# -gt 0 ]]; then printf " %q" "$@" >> "$log"; fi' \
  'printf "\n" >> "$log"' \
  'if [[ "${1:-}" == "-C" && "${3:-}" == "remote" && "${4:-}" == "get-url" ]]; then' \
  '  printf "%s\n" "${GIT_ORIGIN_URL:-https://github.com/daniel-baez/dotfiles.git}"' \
  '  exit 0' \
  'fi' \
  'if [[ "${1:-}" == "-C" && "${3:-}" == "pull" ]]; then' \
  '  exit "${GIT_PULL_EXIT:-0}"' \
  'fi' \
  'exit 0'

block_stub() {
  local name="$1"
  write_stub "$name" \
    'set -euo pipefail' \
    'printf "%s" "'"$name"'" >> "${SUDO_LOG:?}"' \
    'if [[ $# -gt 0 ]]; then printf " %q" "$@" >> "$SUDO_LOG"; fi' \
    'printf "\n" >> "$SUDO_LOG"' \
    'printf "unexpected '"$name"': %s\n" "$*" >&2' \
    'exit 99'
}

block_stub sudo
block_stub apt-get
block_stub dnf
block_stub wget
block_stub curl
block_stub brew

fresh() {
  HOME="$(mktemp -d "$TMP/home.XXXXXX")"
  GH_LOG="$HOME/gh.log"
  GIT_LOG="$HOME/git.log"
  SUDO_LOG="$HOME/sudo.log"
  INSTALL_ARGS_FILE="$HOME/install.args"
  : >"$GH_LOG"
  : >"$GIT_LOG"
  : >"$SUDO_LOG"
  rm -f "$INSTALL_ARGS_FILE"
  INIT_UNAME_S="Linux"
  INIT_UNAME_M="x86_64"
  INIT_OS_RELEASE=""
  INIT_DPKG_ARCH=""
  GH_STATUS_EXIT=0
  GH_LOGIN="daniel-baez"
  GH_LOGIN_SEQUENCE_FILE=""
  GIT_ORIGIN_URL="https://github.com/daniel-baez/dotfiles.git"
  GIT_PULL_EXIT=0
  INSTALL_EXIT=0
  XDG_CURRENT_DESKTOP=""
  DESKTOP_SESSION=""
  WITH_GH_TOKEN=""
  WITH_GITHUB_TOKEN=""
}

build_env() {
  ENV_ARGS=(
    env -i
    "HOME=$HOME"
    "PATH=$STUB_BIN:/usr/bin:/bin"
    "USER=${USER:-tester}"
    "LOGNAME=${USER:-tester}"
    "SHELL=/bin/bash"
    "TERM=xterm"
    "LANG=C"
    "LC_ALL=C"
    "INIT_TEST_MODE=1"
    "GH_LOG=$GH_LOG"
    "GIT_LOG=$GIT_LOG"
    "SUDO_LOG=$SUDO_LOG"
    "INSTALL_ARGS_FILE=$INSTALL_ARGS_FILE"
    "GH_STATUS_EXIT=$GH_STATUS_EXIT"
    "GH_LOGIN=$GH_LOGIN"
    "GIT_ORIGIN_URL=$GIT_ORIGIN_URL"
    "GIT_PULL_EXIT=$GIT_PULL_EXIT"
    "INSTALL_EXIT=$INSTALL_EXIT"
  )
  if [[ -n "$INIT_UNAME_S" ]]; then
    ENV_ARGS+=("INIT_UNAME_S=$INIT_UNAME_S")
  fi
  if [[ -n "$INIT_UNAME_M" ]]; then
    ENV_ARGS+=("INIT_UNAME_M=$INIT_UNAME_M")
  fi
  if [[ -n "$INIT_OS_RELEASE" ]]; then
    ENV_ARGS+=("INIT_OS_RELEASE=$INIT_OS_RELEASE")
  fi
  if [[ -n "$INIT_DPKG_ARCH" ]]; then
    ENV_ARGS+=("INIT_DPKG_ARCH=$INIT_DPKG_ARCH")
  fi
  if [[ -n "$GH_LOGIN_SEQUENCE_FILE" ]]; then
    ENV_ARGS+=("GH_LOGIN_SEQUENCE_FILE=$GH_LOGIN_SEQUENCE_FILE")
  fi
  if [[ -n "$XDG_CURRENT_DESKTOP" ]]; then
    ENV_ARGS+=("XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP")
  fi
  if [[ -n "$DESKTOP_SESSION" ]]; then
    ENV_ARGS+=("DESKTOP_SESSION=$DESKTOP_SESSION")
  fi
  if [[ -n "$WITH_GH_TOKEN" ]]; then
    ENV_ARGS+=("GH_TOKEN=$WITH_GH_TOKEN")
  fi
  if [[ -n "$WITH_GITHUB_TOKEN" ]]; then
    ENV_ARGS+=("GITHUB_TOKEN=$WITH_GITHUB_TOKEN")
  fi
}

run_capture() {
  set +e
  INIT_OUT="$("$@" 2>&1)"
  INIT_STATUS=$?
  set -e
}

run_init() {
  build_env
  run_capture "${ENV_ARGS[@]}" bash "$ROOT/init.sh" "$@"
}

run_detached() {
  build_env
  run_capture "${ENV_ARGS[@]}" python3 "$ROOT/tests/run_detached.py" bash "$ROOT/init.sh"
}

run_pty() {
  local answer="$1"
  shift
  build_env
  run_capture "${ENV_ARGS[@]}" env "PTY_ANSWER=$answer" python3 "$ROOT/tests/pty_run.py" bash "$ROOT/init.sh" "$@"
}

fail() {
  printf 'FAIL %s\n%s\n' "$1" "${INIT_OUT:-}" >&2
  exit 1
}

assert_ok() {
  local name="$1"
  if [[ "$INIT_STATUS" -ne 0 ]]; then
    fail "$name (exit $INIT_STATUS)"
  fi
  printf 'ok  %s\n' "$name"
}

assert_fail() {
  local name="$1" needle="$2"
  if [[ "$INIT_STATUS" -eq 0 ]]; then
    fail "$name (expected failure)"
  fi
  if [[ "$INIT_OUT" != *"$needle"* ]]; then
    fail "$name (missing: $needle)"
  fi
  printf 'ok  %s\n' "$name"
}

assert_contains() {
  local name="$1" needle="$2"
  if [[ "$INIT_OUT" != *"$needle"* ]]; then
    fail "$name (missing: $needle)"
  fi
}

assert_not_contains() {
  local name="$1" needle="$2"
  if [[ "$INIT_OUT" == *"$needle"* ]]; then
    fail "$name (unexpected: $needle)"
  fi
}

assert_file_contains() {
  local name="$1" file="$2" needle="$3"
  if ! grep -F -q -- "$needle" "$file"; then
    printf 'FAIL %s (file missing: %s)\n%s\n' "$name" "$needle" "$(cat "$file")" >&2
    exit 1
  fi
}

assert_file_absent_needle() {
  local name="$1" file="$2" needle="$3"
  if grep -F -q -- "$needle" "$file"; then
    printf 'FAIL %s (file has unexpected: %s)\n%s\n' "$name" "$needle" "$(cat "$file")" >&2
    exit 1
  fi
}

assert_no_sudo() {
  local name="$1"
  if [[ -s "$SUDO_LOG" ]]; then
    printf 'FAIL %s invoked a blocked command\n%s\n' "$name" "$(cat "$SUDO_LOG")" >&2
    exit 1
  fi
}

# --- sourcing and help, before any OS fixture ---

out="$(bash -c 'source "$1"; printf "sourced-ok\n"' bash "$ROOT/init.sh")"
[[ "$out" == "sourced-ok" ]]
printf 'ok  sourcing does not run main\n'

run_capture bash "$ROOT/init.sh" --help
assert_ok "help exits 0"
assert_contains "help text" "Usage:"
assert_contains "help install command" "curl -fsSL https://raw.githubusercontent.com/daniel-baez/init/main/init.sh | bash"

run_capture bash -c 'cat "$1" | bash -s -- --help' bash "$ROOT/init.sh"
assert_ok "piped --help runs"
assert_contains "piped help" "Usage:"

# Real os-release on this machine. Stubs block sudo/apt/dnf if detection is wrong.
fresh
INIT_UNAME_S=""
INIT_UNAME_M=""
run_init
assert_fail "this host is not a supported bootstrap target" "unsupported"
assert_no_sudo "host rejection"
[[ ! -d "$HOME/workspace" ]]
assert_file_absent_needle "host rejection does not call gh" "$GH_LOG" "gh "

# --- OS detection through main ---

fresh
INIT_OS_RELEASE="$FIXTURES/ubuntu.os-release"
run_init
assert_fail "ubuntu is rejected" "unsupported"
assert_not_contains "ubuntu is not treated as Debian" "Only Debian 13"
assert_no_sudo "ubuntu"
[[ ! -d "$HOME/workspace" ]]

fresh
INIT_OS_RELEASE="$FIXTURES/debian-bookworm.os-release"
run_init
assert_fail "bookworm is rejected" "trixie"
assert_no_sudo "bookworm"

fresh
INIT_OS_RELEASE="$FIXTURES/raspbian-bookworm.os-release"
run_init
assert_fail "raspbian bookworm is rejected" "trixie"
assert_no_sudo "raspbian bookworm"

fresh
INIT_OS_RELEASE="$FIXTURES/arch.os-release"
run_init
assert_fail "arch is rejected" "unsupported"
assert_no_sudo "arch"

fresh
INIT_OS_RELEASE="$FIXTURES/debian-trixie.os-release"
INIT_DPKG_ARCH="armhf"
run_init
assert_fail "armhf trixie is rejected" "arm64"
assert_no_sudo "armhf"

fresh
INIT_UNAME_S="FreeBSD"
run_init
assert_fail "freebsd is rejected" "unsupported"
assert_no_sudo "freebsd"

# --- happy paths ---

happy_debian() {
  fresh
  INIT_OS_RELEASE="$FIXTURES/debian-trixie.os-release"
  INIT_DPKG_ARCH="$1"
  run_init
  assert_ok "debian trixie $1 installs"
  assert_contains "debian default flags" "--all --non-interactive"
  assert_not_contains "debian is not described as Fedora GNOME" "Fedora GNOME"
  assert_file_contains "debian clones over https" "$GH_LOG" "https://github.com/daniel-baez/dotfiles.git"
  assert_file_contains "debian sets https protocol" "$GH_LOG" "git_protocol"
  assert_file_contains "debian setup-git" "$GH_LOG" "setup-git"
  assert_file_absent_needle "debian skips login when already authenticated" "$GH_LOG" "auth login"
  [[ -d "$HOME/workspace/dotfiles/.git" ]]
  assert_file_contains "installer args" "$INSTALL_ARGS_FILE" "--all"
  assert_file_contains "installer noninteractive" "$INSTALL_ARGS_FILE" "--non-interactive"
  assert_no_sudo "debian trixie $1"
}

happy_debian amd64
happy_debian arm64

fresh
INIT_OS_RELEASE="$FIXTURES/raspi-trixie.os-release"
INIT_DPKG_ARCH="arm64"
run_init
assert_ok "raspberry pi os trixie arm64"
assert_contains "pi default flags" "--all --non-interactive"
assert_no_sudo "raspi"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-workstation.os-release"
XDG_CURRENT_DESKTOP="GNOME"
run_init
assert_ok "fedora gnome session"
assert_contains "fedora gnome label" "Fedora GNOME"
assert_contains "fedora gnome flags" "--all --non-interactive"
assert_no_sudo "fedora gnome"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-workstation.os-release"
run_init
assert_ok "fedora workstation without a session"
assert_contains "workstation label" "Fedora Workstation"
assert_not_contains "workstation without session is not labeled GNOME" "Fedora GNOME:"
assert_contains "workstation flags" "--all --non-interactive"
assert_no_sudo "fedora workstation"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
run_init
assert_ok "fedora server"
assert_not_contains "server is not labeled GNOME" "Fedora GNOME"
assert_contains "server flags" "--all --non-interactive"
assert_no_sudo "fedora server"

fresh
INIT_UNAME_S="Darwin"
INIT_OS_RELEASE=""
run_init
assert_ok "macos with gh already installed"
assert_contains "macos label" "macOS"
assert_contains "macos flags" "--all --non-interactive"
assert_no_sudo "macos"

# Second run updates the checkout instead of cloning again.
fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
run_init
assert_ok "first fedora run clones"
assert_file_contains "first run clones" "$GH_LOG" "repo clone"
: >"$GH_LOG"
: >"$GIT_LOG"
run_init
assert_ok "second fedora run pulls"
assert_contains "second run says pull" "git pull --ff-only"
assert_contains "second run keeps the workspace" "already exists"
assert_file_contains "second run pulls" "$GIT_LOG" "pull"
assert_file_absent_needle "second run does not clone" "$GH_LOG" "repo clone"
assert_no_sudo "second run"

# Piped execution, the curl | bash path.
fresh
INIT_OS_RELEASE="$FIXTURES/fedora-workstation.os-release"
XDG_CURRENT_DESKTOP="GNOME"
build_env
run_capture "${ENV_ARGS[@]}" bash -c 'cat "$1" | bash -s --' bash "$ROOT/init.sh"
assert_ok "piped run with no arguments"
assert_contains "piped fedora gnome" "Fedora GNOME"
assert_file_contains "piped clone" "$GH_LOG" "repo clone"

fresh
INIT_OS_RELEASE="$FIXTURES/debian-trixie.os-release"
INIT_DPKG_ARCH="amd64"
build_env
run_capture "${ENV_ARGS[@]}" bash -c 'cat "$1" | bash -s -- "${@:2}"' bash "$ROOT/init.sh" shell git
assert_ok "piped extra arguments"
assert_file_contains "forwarded shell" "$INSTALL_ARGS_FILE" "shell"
assert_file_contains "forwarded git" "$INSTALL_ARGS_FILE" "git"
assert_file_absent_needle "forwarded args replace --all" "$INSTALL_ARGS_FILE" "--all"
assert_contains "forwarded message" "forwarding arguments"

fresh
INIT_OS_RELEASE="$FIXTURES/debian-trixie.os-release"
INIT_DPKG_ARCH="amd64"
run_init --dry-run shell
assert_ok "direct extra arguments"
assert_file_contains "dry-run forwarded" "$INSTALL_ARGS_FILE" "--dry-run"
assert_file_contains "shell forwarded" "$INSTALL_ARGS_FILE" "shell"
assert_file_absent_needle "direct args replace the default" "$INSTALL_ARGS_FILE" "--non-interactive"

# --- auth ---

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
GH_STATUS_EXIT=1
run_pty ""
assert_ok "login when signed out"
assert_file_contains "web login" "$GH_LOG" "--web"
assert_file_contains "https protocol flag" "$GH_LOG" "--git-protocol"
assert_file_contains "https value" "$GH_LOG" "https"
assert_file_contains "login subcommand" "$GH_LOG" "auth login"
assert_no_sudo "signed out login"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
GH_LOGIN="octocat"
# The answer is the command's stdin, not a pipe around the assertion.
# A pipeline would run the function in a subshell and drop INIT_STATUS.
build_env
set +e
INIT_OUT="$(printf 'y\n' | "${ENV_ARGS[@]}" python3 "$ROOT/tests/run_detached.py" bash "$ROOT/init.sh" 2>&1)"
INIT_STATUS=$?
set -e
assert_fail "wrong user does not read yes from the pipe" "octocat"
assert_contains "wrong user names the expected account" "daniel-baez"
assert_contains "wrong user asks for a terminal" "terminal"
assert_file_absent_needle "pipe does not log out" "$GH_LOG" "auth logout"
assert_file_absent_needle "pipe does not clone" "$GH_LOG" "repo clone"
assert_no_sudo "wrong user without a tty"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
GH_LOGIN="octocat"
run_pty $'n\n'
assert_fail "declining logout stops" "stopped"
assert_contains "decline names the account" "octocat"
assert_file_absent_needle "decline does not log out" "$GH_LOG" "auth logout"
assert_file_absent_needle "decline does not clone" "$GH_LOG" "repo clone"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
GH_LOGIN_SEQUENCE_FILE="$HOME/logins"
printf '%s\n' octocat daniel-baez >"$GH_LOGIN_SEQUENCE_FILE"
run_pty $'y\n'
assert_ok "accepting logout signs in as daniel-baez"
assert_file_contains "logout user" "$GH_LOG" "octocat"
assert_file_contains "logout host" "$GH_LOG" "--hostname"
assert_file_contains "login after logout" "$GH_LOG" "auth login"
assert_file_contains "clone after the right user" "$GH_LOG" "repo clone"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
GH_LOGIN_SEQUENCE_FILE="$HOME/logins"
printf '%s\n' octocat someone-else >"$GH_LOGIN_SEQUENCE_FILE"
run_pty $'y\n'
assert_fail "still the wrong user after retry" "someone-else"
assert_file_absent_needle "failed retry does not clone" "$GH_LOG" "repo clone"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
WITH_GH_TOKEN="test-token-value"
run_init
assert_fail "GH_TOKEN is refused" "GH_TOKEN"
assert_not_contains "GH_TOKEN value is not printed" "test-token-value"
assert_file_absent_needle "GH_TOKEN does not clone" "$GH_LOG" "repo clone"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
WITH_GITHUB_TOKEN="test-token-value"
run_detached
assert_fail "GITHUB_TOKEN is refused without a tty" "GITHUB_TOKEN"
assert_not_contains "GITHUB_TOKEN value is not printed" "test-token-value"

# --- checkout edge cases ---

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
mkdir -p "$HOME/workspace/dotfiles/.git"
GIT_ORIGIN_URL="git@github.com:daniel-baez/dotfiles.git"
cat >"$HOME/workspace/dotfiles/install.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$INSTALL_ARGS_FILE"
EOF
chmod +x "$HOME/workspace/dotfiles/install.sh"
run_init
assert_ok "ssh origin is switched to https then pulled"
assert_contains "switched origin" "setting origin"
assert_file_contains "set-url" "$GIT_LOG" "set-url"
assert_file_contains "pull after set-url" "$GIT_LOG" "pull"
assert_file_contains "https remote" "$GIT_LOG" "https://github.com/daniel-baez/dotfiles.git"
assert_file_absent_needle "existing checkout is not cloned" "$GH_LOG" "repo clone"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
mkdir -p "$HOME/workspace/dotfiles/.git"
GIT_ORIGIN_URL="https://github.com/other/dotfiles.git"
printf '#!/bin/bash\nexit 0\n' >"$HOME/workspace/dotfiles/install.sh"
run_init
assert_fail "foreign origin is refused" "other/dotfiles"
assert_file_absent_needle "foreign origin is not pulled" "$GIT_LOG" "pull"
assert_file_absent_needle "foreign origin is not cloned over" "$GH_LOG" "repo clone"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
mkdir -p "$HOME/workspace/dotfiles"
printf 'not a clone\n' >"$HOME/workspace/dotfiles/README"
run_init
assert_fail "non-git directory is left alone" "not a git clone"
[[ -f "$HOME/workspace/dotfiles/README" ]]
assert_file_absent_needle "non-git directory is not cloned over" "$GH_LOG" "repo clone"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
mkdir -p "$HOME/workspace"
: >"$HOME/workspace/dotfiles"
run_init
assert_fail "a file in the way is left alone" "not a directory"
[[ -f "$HOME/workspace/dotfiles" ]]

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
mkdir -p "$HOME/workspace/dotfiles/.git"
GIT_PULL_EXIT=1
printf '#!/bin/bash\nexit 0\n' >"$HOME/workspace/dotfiles/install.sh"
run_init
assert_fail "pull that cannot fast-forward stops" "ff-only"
[[ ! -f "$INSTALL_ARGS_FILE" ]]

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
mkdir -p "$HOME/workspace/dotfiles/.git"
run_init
assert_fail "checkout without install.sh stops" "installer not found"

fresh
INIT_OS_RELEASE="$FIXTURES/fedora-server.os-release"
INSTALL_EXIT=7
run_init
assert_fail "installer failure is reported" "exit 7"

# --- apt repository line, without root or network ---

apt_case() {
  local arch="$1" expect_status="$2"
  local case_tmp out status
  case_tmp="$(mktemp -d "$TMP/apt.XXXXXX")"
  set +e
  out="$(
    {
      set -euo pipefail
      export PATH="/usr/bin:/bin"
      export INIT_TEST_MODE=1
      export INIT_DPKG_ARCH="$arch"
      # shellcheck source=../init.sh
      source "$ROOT/init.sh"
      RUN_LOG="$case_tmp/run.log"
      CAPTURE="$case_tmp/capture"
      mkdir -p "$CAPTURE"
      : >"$RUN_LOG"
      sudo() { printf 'sudo called\n' >&2; exit 97; }
      apt-get() { printf 'apt-get called\n' >&2; exit 97; }
      dnf() { printf 'dnf called\n' >&2; exit 97; }
      wget() {
        local dest=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -O)
              dest="$2"
              shift 2
              ;;
            -O*)
              dest="${1#-O}"
              shift
              ;;
            *) shift ;;
          esac
        done
        printf 'keyring-bytes' >"$dest"
      }
      run_root() {
        printf '%s\n' "$*" >>"$RUN_LOG"
        if [[ "$1" == "tee" ]]; then
          cat >"$CAPTURE/$(basename "$2")"
        fi
      }
      install_gh_debian
    } 2>&1
  )"
  status=$?
  set -e
  INIT_OUT="$out"
  INIT_STATUS=$status
  if [[ "$expect_status" -eq 0 ]]; then
    if [[ "$status" -ne 0 ]]; then
      fail "apt $arch (exit $status)"
    fi
    local list="$case_tmp/capture/github-cli.list"
    local want="deb [arch=${arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
    if [[ "$(cat "$list")" != "$want" ]]; then
      printf 'FAIL apt list for %s\n want: %s\n got:  %s\n' "$arch" "$want" "$(cat "$list")" >&2
      exit 1
    fi
    [[ "$(cat "$case_tmp/capture/githubcli-archive-keyring.gpg")" == "keyring-bytes" ]]
    grep -F -q "chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg" "$case_tmp/run.log"
    grep -F -q "apt-get install -y gh" "$case_tmp/run.log"
    printf 'ok  apt repo line %s\n' "$arch"
  else
    if [[ "$status" -eq 0 ]]; then
      fail "apt $arch should have failed"
    fi
    if [[ -s "$case_tmp/run.log" ]]; then
      printf 'FAIL apt %s changed the package setup\n%s\n' "$arch" "$(cat "$case_tmp/run.log")" >&2
      exit 1
    fi
    assert_contains "apt $arch reason" "arm64"
    printf 'ok  apt rejects %s\n' "$arch"
  fi
}

apt_case arm64 0
apt_case amd64 0
apt_case armhf 1

# macOS as root must stop before Homebrew.
set +e
out="$(
  {
    set -euo pipefail
    # shellcheck source=../init.sh
    source "$ROOT/init.sh"
    id() { printf '0\n'; }
    curl() { printf 'curl called\n' >&2; exit 97; }
    install_gh_macos
  } 2>&1
)"
status=$?
set -e
INIT_OUT="$out"
INIT_STATUS=$status
assert_fail "macos root is refused" "not installed as root"
assert_not_contains "macos root does not download Homebrew" "curl called"

# gh already on PATH is not reinstalled.
set +e
out="$(
  {
    set -euo pipefail
    export PATH="$STUB_BIN:/usr/bin:/bin"
    export GH_LOG="$TMP/skip-gh.log"
    export SUDO_LOG="$TMP/skip-sudo.log"
    : >"$GH_LOG"
    : >"$SUDO_LOG"
    # shellcheck source=../init.sh
    source "$ROOT/init.sh"
    # Read by install_github_cli after source.
    # shellcheck disable=SC2034
    OS_KIND="debian"
    install_github_cli
  } 2>&1
)"
status=$?
set -e
INIT_OUT="$out"
INIT_STATUS=$status
assert_ok "existing gh is kept"
assert_contains "existing gh version" "already installed"
assert_contains "existing gh version string" "gh version 9.9.9"
[[ ! -s "$TMP/skip-sudo.log" ]]

printf '\nall tests passed\n'
