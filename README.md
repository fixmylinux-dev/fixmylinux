# fixmylinux

Sets up the things a fresh Fedora install leaves out, in one command.

```
curl -fsSL https://fixmylinux.dev/setup.sh | bash
```

Instructions for KDE, GNOME and the terminal are on [fixmylinux.dev](https://fixmylinux.dev).

## What it does

1. Updates your system
2. Adds the [RPM Fusion](https://rpmfusion.org) repositories
3. Swaps Fedora's `ffmpeg-free` for the full `ffmpeg` and updates the multimedia packages
4. Turns on hardware video decoding: `mesa-va-drivers-freeworld` for AMD, `intel-media-driver` for Intel
5. Adds Flathub without Fedora's filter, and Flatpak support in Discover on KDE

It asks before changing anything, skips anything that's already set up, and prints every command before running it. A log is saved to `~/fixmylinux.log`.

It does not install NVIDIA drivers or DVD decryption, collect any data, or download any more code. Everything it installs comes from Fedora, RPM Fusion or Flathub.

To see what it would do without changing anything:

```
curl -fsSLO https://github.com/fixmylinux-dev/fixmylinux/releases/latest/download/setup.sh
bash setup.sh --dry-run
```

## Supported

Fedora 41 and newer. Tested on Fedora KDE Plasma.

Atomic systems (Silverblue, Kinoite, Bazzite, Aurora) aren't supported.

## Checking a release

`fixmylinux.dev/setup.sh` redirects to the latest [release](https://github.com/fixmylinux-dev/fixmylinux/releases). Releases are built by the public [release workflow](.github/workflows/release.yml), not on anyone's computer, and can't be edited after they're published.

To check a download came from this repo:

```
gh attestation verify setup.sh --repo fixmylinux-dev/fixmylinux
```

Or compare it with the `SHA256SUMS` file on the release page:

```
sha256sum setup.sh
```

## Making a release

1. Change `VERSION` at the top of `setup.sh` and commit it
2. Go to **Actions → Release → Run workflow**

The workflow tags the commit (e.g. `v0.2.0`) and publishes the release. It refuses to run if that version has already been released.

## Contributing

Issues and pull requests are welcome.

## Licence

MIT. The "fixmylinux" name and logo are not covered by this licence and may not be used to imply endorsement or for forks without permission.

Not affiliated with Fedora, Red Hat, KDE or GNOME.
