# gilliserver

The configuration of **gilliserver**, a Raspberry Pi 3 Model B running DietPi as an always-on home
server. Everything it runs is reachable over [Tailscale](https://tailscale.com); nothing is
port-forwarded on the router.

| Spec        | Value                                    |
| ----------- | ---------------------------------------- |
| **HW**      | Raspberry Pi 3 Model B (1 GB RAM)        |
| **OS**      | DietPi (Bookworm, `DietPi_RPi234-ARMv8`) |
| **Network** | Tailscale, ethernet to the LAN           |

What it is for, in the order it is being built:

1. Run an [Omnigent](https://omnigent.ai) server, reachable from anywhere on the tailnet.
2. Wake sleeping machines on the LAN — the Steam Machine first — so agents can run on real hardware
   without anything staying powered on. The Pi is the one box that never sleeps, so it is the one
   that sends the magic packet.
3. Later: Home Assistant and whatever else, always behind Tailscale.

## The one rule

**Nothing is configured by hand.** Every change to the Pi lives in this repo as a file, and the Pi
rebuilds itself from this repo on every boot and every hour after that. A change you `ssh` in and
make yourself is gone at the next apply — which is the point: a reflash has to be boring.

Agents working on this repo: read [AGENTS.md](./AGENTS.md).

**This repo is public, so no secret ever goes in it.** They live in `gilliserver.env` on the
device's boot partition — `/boot/firmware/gilliserver.env` on current DietPi RPi images, `/boot/gilliserver.env`
on older ones; `apply.sh` finds whichever is there. A `pre-commit` hook and a CI job
(`scripts/check-secrets.sh`) refuse anything that looks like a credential. Hooks aren't cloned with
a repo, so a fresh clone needs one command:

```bash
scripts/install-hooks.sh
```

## How it works

DietPi's own config-as-code is the boot partition: `dietpi.txt` drives the entire first boot
(hostname, locale, which software to install, non-interactively), and
`Automation_Custom_Script.sh` runs once at the end of it. That is all we use it for — it gets the
repo onto the box and hands over.

From there, `scripts/apply.sh` is the deployment:

```
git pull  →  copy config/ onto the filesystem, path for path  →  run modules/ in order
```

It runs from `gilliserver-apply.service` at boot and from `gilliserver-apply.timer` every hour, so a
push to `main` lands within the hour without anyone touching the Pi.

```
boot/                       goes on the SD card's FAT partition, before first boot
  dietpi.overrides            keys applied onto the card's stock dietpi.txt
  Automation_Custom_Script.sh first boot: install git, clone this repo, run apply.sh
  gilliserver.env.example     names of the secrets — the filled-in copy lives only on the SD card
config/                     mirrors the filesystem: config/etc/foo → /etc/foo
  etc/systemd/system/         units (auto-enabled if they have an [Install] section)
  etc/gilliserver/            our own config, e.g. the wake-on-lan device list
  usr/local/bin/              commands, e.g. gilli-wake
modules/                    one idempotent script per concern, run in filename order
scripts/                    apply.sh (the deployment itself), check-secrets.sh, install-hooks.sh
setup/                      scripts you run from your laptop, not on the Pi
```

`config/` is dumb on purpose: a file there is copied to the matching absolute path, nothing more.
Anything that needs a decision — install a package, join a tailnet, restart a service — is a module.

## Setting up a new Pi

Flash [DietPi for the RPi](https://dietpi.com/#download) (`DietPi_RPi234-ARMv8-Bookworm` for a Pi 3)
onto an SD card, leave it in the reader, and run:

```bash
setup/prepare-sdcard.sh              # finds the boot partition itself
```

Fill in `TAILSCALE_AUTHKEY` in the `gilliserver.env` it created on the card
([get a key here](https://login.tailscale.com/admin/settings/keys)), eject, put the card in the Pi,
plug in ethernet, and power it on. The first boot installs DietPi's own software before it ever
reaches our bootstrap, so give it half an hour or so.

```bash
ssh root@gilliserver.local 'tail -f /root/.gilliserver-bootstrap.log'
```

Then it is on the tailnet and pulling this repo by itself.

### Onto a box that is already running

This is the path that has actually been walked — gilliserver itself was a meeting-room kiosk first.
Nothing is flashed; the repo takes the box over from the inside.

```bash
ssh root@<the-box>
apt-get install -y git
git clone https://github.com/Gi11i4m/gilliserver /opt/gilliserver
/opt/gilliserver/scripts/apply.sh
```

Two things first boot would have done that this does not, so do them by hand once:

```bash
/boot/dietpi/func/change_hostname gilliserver
/boot/dietpi/dietpi-autostart 7        # console, not a desktop
```

Then put `TAILSCALE_AUTHKEY` in `gilliserver.env` on the boot partition and apply again. Everything
else — packages, DietPi software IDs, Tailscale itself — `modules/05-packages.sh` and
`modules/10-tailscale.sh` install on their own, precisely so that a repurposed box and a freshly
flashed one end up the same.

Whatever the box ran before is your problem to remove, and it is worth being thorough: its own
config management will happily fight this one. For the kiosk that meant its update-and-run unit, its
cron jobs, its scripts in `/root`, and the Chromium autostart.

## Changing something

Commit to `main` and wait up to an hour, or don't wait:

```bash
setup/apply-now.sh           # ssh in, pull, apply
setup/apply-now.sh --local   # push the working tree first, for trying something out
```

Debugging:

```bash
tail -f /root/.gilliserver-apply.log    # what the last apply did (and why it failed)
systemctl status gilliserver-apply      # last run
systemctl list-timers gilliserver-apply # when the next one is
/opt/gilliserver/scripts/apply.sh       # run it now, by hand
```

The log is a file rather than only `journalctl` because DietPi keeps `/var/log` in RAM — anything
journald wrote about a run that ended in a reboot is gone before you can read it.

## What is running

Verified on the real Pi on 16 September 2026, on the box that used to be the `sauna` meeting-room
kiosk — not on a fresh flash. Hostname, Tailscale, the hourly timer, the boot-time apply and the
Omnigent server were all exercised end to end, including across reboots.

- **Omnigent**, at **https://gilliserver.tail2b0581.ts.net/** — no port — from
  `gilliserver-omnigent.service`, with `tailscale serve` terminating TLS in front of it.

  `https://…:6767/` does *not* work and never will: Omnigent speaks plain HTTP, so a browser
  pointed at that port fails the TLS handshake with `wrong version number` and looks like a box
  that is down. Either use the URL above, or `http://` on 6767.

  It binds `0.0.0.0`, which makes Omnigent switch itself into accounts mode, so the first person to
  open it creates the admin account. That bind is the reason for the login — pointing it at
  `127.0.0.1` and letting `serve` do the exposing would look tidier and would hand every node on
  the tailnet an unauthenticated server. Roughly 50 seconds from
  start to first request on this hardware, and it idles around 270 MB — the README used to warn you
  would need a swapfile, and you do not: DietPi already ships 1 GB of swap and nothing touched it.
  No model API key lives on the box; agents run on the machines connected to it.
- **The apply loop.** `gilliserver-apply.service` at boot and `gilliserver-apply.timer` hourly,
  both confirmed after a reboot. Two applies in a row are quiet.
- **A nightly self-update**, `gilliserver-update.timer` at 04:00: `apt full-upgrade`,
  `dietpi-update`, and an Omnigent upgrade that restarts the server only if the version moved.
  Kept out of `apply.sh` on purpose — that runs hourly and must stay fast, and a config push should
  not be able to trigger twenty minutes of apt and a reboot.

  It reboots only when the running kernel is older than the newest one in `/boot`.
  `/var/run/reboot-required` is checked too but nothing on this box writes it, so on its own it
  would have meant kernel updates installing and never running. Verified: it upgraded
  6.12.96 → 6.12.109 and rebooted into it.

  `/root/.gilliserver-update.log` is what it did last night.
- **An exit node.** `modules/10-tailscale.sh` advertises `0.0.0.0/0` and `::/0`, and
  `config/etc/sysctl.d/99-gilliserver-forwarding.conf` turns on the forwarding it needs. Advertising
  is all the box can do by itself: a node is not selectable until someone approves it under
  **Machines → gilliserver → … → Edit route settings → Use as exit node** in the Tailscale admin
  console. Until then `tailscale status --json` reports `"ExitNodeOption": false` and it will not
  appear in any client's exit-node list.

  Do not expect much of it. A Pi 3 B reaches the internet over 100 Mb ethernet hung off USB, and
  WireGuard on that CPU is the tighter limit of the two — this is an exit node for having a Belgian
  IP from a hotel, not for saturating a link.

## What is not done yet

- **Wake-on-LAN device list.** `config/etc/gilliserver/devices.conf` still has the placeholder MAC
  for the Steam Machine, so `gilli-wake steam-machine` does nothing and has never been tested
  against real hardware. `modules/20-wake-on-lan.sh` says so on every apply until it is filled in.
  When you do: check WoL is enabled in the Steam Machine's firmware *and* its OS — most desktops
  switch it off on shutdown.
- **Tailscale node key expiry.** gilliserver joined with an untagged key, so it is owned by a user
  account and its node key expires in a few months — at which point the box drops off the tailnet
  with nobody there to re-authenticate it. Either disable key expiry for it in the admin console,
  or re-join with a tagged key (a tag disables expiry, but needs an ACL entry, and Tailscale SSH to
  a tagged node needs its own `ssh` rule).
- **`setup/prepare-sdcard.sh` is unverified.** It looks for `dietpi.txt` on the card's FAT
  partition. On the running box `dietpi.txt` is on ext4 at `/boot` and the FAT partition is
  `/boot/firmware`, which a laptop cannot read — so this may not find anything on a current image.
  gilliserver was installed from the running-box end instead, never from a card.
- **A reflash has not been tried.** Everything here is now reproducible in principle, but the only
  path actually walked is the one onto an already-running Debian.
- **Backups.** Nothing on the Pi is backed up. Omnigent's SQLite database at
  `/root/.omnigent/chat.db` is the first thing on the box that is real state, so the assumption
  that there is nothing worth keeping no longer quite holds.
