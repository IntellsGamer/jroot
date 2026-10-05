# Official plugins

Maintained alongside JRoot core. Install any of them with:

```bash
jroot plugin install ./plugins/<name>
jroot plugin verify <name>
```

| Plugin | What it does |
|---|---|
| [ssh-guard](ssh-guard/) | Jail SSH watchdog + brute-force monitor. Reports dead daemons, counts auth failures per source IP from each daemon's own log, optionally stops a daemon under active attack. |
