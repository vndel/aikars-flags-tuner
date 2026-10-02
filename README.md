# aikars-flags-tuner

![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white) ![systemd](https://img.shields.io/badge/systemd-FCC624?logo=linux&logoColor=black) ![shellcheck](https://img.shields.io/badge/shellcheck-clean-success) ![License](https://img.shields.io/badge/License-MIT-green)

> JVM flag generation and systemd units for Paper servers. Heap sizing and GC
> selection are computed, not copy-pasted.

## Why a script

Heap size and collector choice are not independent decisions, and the common
advice ("use Aikar's flags") omits the parts that depend on your machine.

```bash
./bin/generate-flags.sh              # auto-detect RAM, pick a collector
./bin/generate-flags.sh -m 8         # 8GB heap
./bin/generate-flags.sh -m 24 -g zgc -o start.sh
```

## What it gets right

**`Xms` is pinned to `Xmx`.** A growing heap makes the collector re-tune its
region sizing while the server is live, which surfaces as tick spikes. Fixing
both ends removes that entirely.

**Heap is not set to total RAM.** The JVM also needs metaspace, thread stacks
and direct buffers, and the OS needs page cache for region files. The script
reserves headroom on a sliding scale:

| Total RAM | Heap allocated | Reserved |
|---|---|---|
| 4GB | 3GB | 1GB |
| 8GB | 6GB | 2GB |
| 16GB | 13GB | 3GB |
| 32GB+ | total - 6GB | 6GB |

**Collector is chosen by heap size.** G1 below 16GB, generational ZGC at or
above it. G1's pause behaviour is predictable at 4-12GB; ZGC only wins once G1
full-collection pauses get long enough to matter.

**It warns above 31GB.** Past ~32GB the JVM drops compressed object pointers and
every reference widens from 4 to 8 bytes. A 31GB heap frequently holds *more*
live data than a 33GB one.

## Verified behaviour

```
$ ./bin/generate-flags.sh
[generate-flags.sh] detected 7GB total, allocating 5GB heap
[generate-flags.sh] selected collector: g1

$ ./bin/generate-flags.sh -m 40 >/dev/null
[generate-flags.sh] warning: heap >31GB disables compressed oops; 31GB is usually better

$ ./bin/generate-flags.sh -m abc
[generate-flags.sh] error: memory must be an integer
```

Both scripts pass `shellcheck` with no warnings and use `set -Eeuo pipefail`.

## GC log analysis

```bash
./bin/gc-report.sh logs/gc.log
```

Reports mean, p95 and max pause plus **the count of pauses over 50ms** — the
tick budget. Average pause is the wrong metric: a 2ms mean with occasional 300ms
outliers is a visibly stuttering server.

## systemd

`systemd/minecraft@.service` is a template unit — one instance per server:

```bash
sudo cp systemd/minecraft@.service /etc/systemd/system/
sudo systemctl enable --now minecraft@survival
```

Two things it does that matter:

**Stop goes through RCON, not SIGTERM.**

```ini
ExecStop=/usr/local/bin/mcrcon -H 127.0.0.1 -P 25575 -p "${RCON_PASSWORD}" stop
TimeoutStopSec=180
```

Killing the JVM mid-chunk-write is how worlds get corrupted. `stop` lets Paper
flush regions and player data first, and 180s gives a large world time to
finish.

**It is sandboxed.** A Minecraft server runs arbitrary plugin code, so
`ProtectSystem=strict` plus `ReadWritePaths` confines it to its own directory.

The RCON password lives in an `EnvironmentFile` (mode 0600), never on the
command line where any local user could read it from `ps`.

## License

MIT — see [LICENSE](LICENSE).
