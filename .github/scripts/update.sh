#!/usr/bin/env bash
# Bump nightcap-git when upstream publishes a new v* release tag, verify that
# the package still builds, then publish PKGBUILD + .SRCINFO to GitHub and AUR.
#
# Runs as root inside an archlinux:base-devel container.
#
# Environment:
#   FORCE=true               bump to the latest upstream commit even without a new tag
#   DRY_RUN=true             build and report, but push nothing
#   AUR_SSH_PRIVATE_KEY      key allowed to push to aur@aur.archlinux.org
#   GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL   identity for the commits
set -euo pipefail

UPSTREAM=https://github.com/CoderDayton/nightcap.git
AUR_REPO=ssh://aur@aur.archlinux.org/nightcap-git.git
AUR_HOST_KEY='aur.archlinux.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEuBKrPzbawxA/k2g6NcyV5jmqwJ2s+zpgZGZ7tpLIcN'
FORCE=${FORCE:-false}
DRY_RUN=${DRY_RUN:-false}
WORKDIR=$(pwd)

log() { printf '==> %s\n' "$*"; }
output() { [[ -n ${GITHUB_OUTPUT:-} ]] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT" || true; }

current_pkgver=$(sed -n 's/^pkgver=//p' PKGBUILD)
current_tag=${current_pkgver%%.r*}

# Cheap check first: skip the clone and build when no newer tag exists.
latest_tag=$(git ls-remote --tags --refs "$UPSTREAM" 'v[0-9]*' \
  | sed 's|.*refs/tags/v||' | sort -V | tail -n1)
log "Packaged release: $current_tag, latest upstream release: ${latest_tag:-none}"

if [[ $FORCE != true ]]; then
  if [[ -z $latest_tag ]] || [[ $(printf '%s\n%s\n' "$latest_tag" "$current_tag" | sort -V | tail -n1) == "$current_tag" ]]; then
    log "No new release tag; nothing to do."
    output updated false
    exit 0
  fi
fi

# makepkg refuses to run as root.
id builder &>/dev/null || useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/builder
chown -R builder: "$WORKDIR"
as_builder() { sudo -u builder -H "$@"; }

log "Building package (also computes the new pkgver)"
as_builder makepkg --syncdeps --noconfirm --force --cleanbuild

new_pkgver=$(sed -n 's/^pkgver=//p' PKGBUILD)
new_tag=${new_pkgver%%.r*}
log "New pkgver: $new_pkgver"

# The tag may exist upstream without being reachable from main yet.
if [[ $FORCE != true && $new_tag == "$current_tag" ]]; then
  log "Release $latest_tag is not on main yet; not publishing."
  git checkout -- PKGBUILD
  output updated false
  exit 0
fi
if [[ $new_pkgver == "$current_pkgver" ]]; then
  log "pkgver unchanged; nothing to publish."
  output updated false
  exit 0
fi

as_builder makepkg --printsrcinfo > .SRCINFO
output updated true
output pkgver "$new_pkgver"

if [[ $DRY_RUN == true ]]; then
  log "Dry run: not pushing. Diff:"
  git --no-pager diff -- PKGBUILD .SRCINFO
  exit 0
fi

: "${GIT_AUTHOR_NAME:?}" "${GIT_AUTHOR_EMAIL:?}" "${AUR_SSH_PRIVATE_KEY:?}"
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
message="Update to $new_pkgver"

log "Publishing to AUR"
# Absolute paths: ssh resolves ~ from passwd, not $HOME (which differs in CI).
ssh_dir=$(mktemp -d)
trap 'rm -rf "$ssh_dir"' EXIT
printf '%s\n' "$AUR_SSH_PRIVATE_KEY" > "$ssh_dir/aur"
chmod 600 "$ssh_dir/aur"
printf '%s\n' "$AUR_HOST_KEY" > "$ssh_dir/known_hosts"
export GIT_SSH_COMMAND="ssh -i $ssh_dir/aur -o IdentitiesOnly=yes -o UserKnownHostsFile=$ssh_dir/known_hosts -o StrictHostKeyChecking=yes"

aur_dir=$(mktemp -d)
git clone "$AUR_REPO" "$aur_dir"
cp PKGBUILD .SRCINFO "$aur_dir"/
git -C "$aur_dir" add PKGBUILD .SRCINFO
if git -C "$aur_dir" diff --cached --quiet; then
  log "AUR already up to date."
else
  git -C "$aur_dir" commit -m "$message"
  git -C "$aur_dir" push origin HEAD:master
fi
# GitHub last: if the AUR push fails, the next run retries the whole bump.
log "Committing to GitHub"
git add PKGBUILD .SRCINFO
git commit -m "$message"
git push origin HEAD
log "Done: $new_pkgver"
