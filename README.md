# nightcap-git (AUR)

Packaging for [nightcap-git](https://aur.archlinux.org/packages/nightcap-git),
built from [CoderDayton/nightcap](https://github.com/CoderDayton/nightcap).

The `Update AUR package` workflow runs every 6 hours. When upstream publishes a
new `v*` release tag on `main`, it builds the package in an Arch container,
regenerates `.SRCINFO`, and pushes the bump here and to the AUR. Commits
between releases are not pushed (per AUR guidelines); AUR helpers pick those
up with devel checks:

```sh
yay -Y --gendb && yay -Y --devel --save     # yay
paru --gendb                                # paru, then set Devel in paru.conf
```

Manual runs (Actions → Update AUR package → Run workflow) accept:

- `force`: bump to the latest upstream commit even without a new tag
- `dry_run`: build and show the diff without pushing

Requires the `AUR_SSH_PRIVATE_KEY` repository secret, whose public key is
registered on the AUR account.
