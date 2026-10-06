# ssh-guard

Jail SSH watchdog + brute-force monitor for JRoot. Watches every jail with an
SSH daemon: reports dead daemons, counts auth failures per source IP straight
from each daemon's own log, and can stop a daemon under active attack.

```bash
jroot plugin install ./ssh-guard
jroot plugin verify ssh-guard

jroot ssh-guard status
jroot ssh-guard threshold 10
jroot ssh-guard mode stop
jroot ssh-guard allowlist add 203.0.113.7

jroot plugin service start ssh-guard on_watch 60
jroot plugin service status ssh-guard
```

Notes:

- Default mode is `alert` (log only). `stop` mode stops the attacked jail's
  daemon via `jroot ssh <jail> stop`; intentionally stopped jails (seen via
  the `on_stop` hook) are never flagged.
- Offender counts come from newly appended log bytes only (offset-tracked per
  jail), so restarts and log truncation never double-count.
- `jroot-dev.py test` times out on the `on_watch` service hook by design (it
  loops); validate with `validate --strict` plus
  `simulate on_stop` / `simulate on_watch once`.
