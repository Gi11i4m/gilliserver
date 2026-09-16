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
  gilliserver.env.example     secrets template — the filled-in copy is never committed
config/                     mirrors the filesystem: config/etc/foo → /etc/foo
  etc/systemd/system/         units (auto-enabled if they have an [Install] section)
  etc/gilliserver/            our own config, e.g. the wake-on-lan device list
  usr/local/bin/              commands, e.g. gilli-wake
modules/                    one idempotent script per concern, run in filename order
scripts/apply.sh            the deployment itself
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

## What is not done yet

- **Omnigent as a service.** `modules/30-omnigent.sh` installs the CLI but nothing runs it yet, and
  none of it has been tried on the actual hardware. Omnigent wants Python 3.12+, Node 22 and tmux;
  a Pi 3 B has 1 GB of RAM and no swap by default, so expect to add a swapfile. Whoever gets it
  working first: commit what you changed, don't leave it only on the box.
- **Wake-on-LAN device list.** `config/etc/gilliserver/devices.conf` has a placeholder MAC for the
  Steam Machine. Fill in the real one, and check that WoL is enabled in both its firmware and its
  OS — most desktops switch it off on shutdown.
- **Backups.** Nothing on the Pi is backed up; the assumption is that it holds no state worth
  keeping. The first service that breaks that assumption needs a plan.
