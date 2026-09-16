# Working on gilliserver

Read [README.md](./README.md) first — it explains what the box is and how `apply.sh` deploys it.

## The rule

**Every change to the Raspberry Pi must land in this repo.** If you `ssh` into gilliserver and
change something, you have not finished the job: the next apply overwrites it and a reflash loses
it. Reproducing the whole box from a blank SD card has to stay a one-command operation.

So, for any change:

1. Write it as a file in this repo (`config/`, `modules/`, or `boot/`).
2. Get it onto the Pi with `setup/apply-now.sh`, not by editing files there.
3. Commit it.

Exploring on the box with `ssh` to find out *what* to write is fine and expected. Leaving the result
there is not.

## Where a change goes

| What you are changing                                        | Where                                                |
| ------------------------------------------------------------ | ---------------------------------------------------- |
| A file with a fixed path on the Pi (unit, config, script)      | `config/<its absolute path without the leading />`    |
| Anything that needs a decision: packages, services, joining a network | a module in `modules/`                        |
| Something that must be true before first boot finishes          | `boot/dietpi.overrides` or `boot/Automation_Custom_Script.sh` |
| A secret                                                        | `/boot/gilliserver.env` on the device, never the repo |

`config/` is a dumb path-for-path copy. Files land at their matching absolute path, systemd units
with an `[Install]` section are enabled automatically, and `systemctl daemon-reload` runs when any
unit changed. Nothing in `config/` can run logic — that is what modules are for.

## Writing a module

`modules/NN-name.sh`, run in filename order on every boot **and every hour**. Therefore:

- **Idempotent, always.** Check before you install, create, or append. A module that appends a line
  to a file every run is a bug that takes a month to notice.
- **Fail loudly, not fatally.** `apply.sh` keeps going when a module fails and logs it. Do not let a
  broken module take the rest of the deployment with it.
- **Restart what you own.** `apply.sh` only reloads the systemd daemon; it does not restart
  services, because restarting itself mid-run is a good way to lose a box. If your module's unit
  needs a restart when its config changed, do that in the module.
- **Say why, not what, in comments.** The commands are readable; the reason a Pi 3 needs them is
  not. Every non-obvious line here exists because something failed once.

## Secrets

Secrets live in `/boot/gilliserver.env` on the device — the FAT partition, so it can be filled in
from a laptop with the SD card in hand, and it survives wiping `/opt`. `apply.sh` sources it and
exports it, so modules just read `$TAILSCALE_AUTHKEY` and friends. Add new ones to
`boot/gilliserver.env.example` (name and comment only, never a value).

Nothing secret goes in this repo. It is on GitHub.

## Verifying

There is no test suite; the Pi is the test. Before claiming something works:

```bash
bash -n <script>             # at minimum, on any script you touched
setup/apply-now.sh           # then read the log it prints
```

Run `apply.sh` twice and check the second run is quiet. If it reports changes both times, something
is not idempotent.

If you cannot reach the hardware, say so and say what is unverified — in the commit and in the
README's "What is not done yet". Do not describe untested config as working.
