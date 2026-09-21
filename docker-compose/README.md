# Splunk Homelab

A standalone Splunk deployment on a Synology DS224+ via Docker Compose, correlating the same
network telemetry already covered by [wazuh-homelab](https://github.com/nloftis/wazuh-homelab)
and [opnsense-observability-stack](https://github.com/nloftis/opnsense-observability-stack) —
this time through a second, independent collection and search pipeline.

## Rationale

Wazuh and Grafana/Loki already provide detection and observability across the home network.
This project asks a different question: what does the same event data look like through a
commercial SIEM's ingestion, indexing, and search model, and how does that compare in practice
— not just on paper — to an open-source stack running on the same hardware?

Running both stacks concurrently isn't necessary to answer that. This project toggles between
Splunk and Wazuh's indexer rather than running them side by side, keeping each one's resource
footprint isolated and measurable on a NAS with a fixed 6GB memory ceiling.

## Alternatives considered and rejected

- **Running Wazuh and Splunk concurrently** — rejected. Two JVM-adjacent indexing engines
  (Wazuh's OpenSearch-based indexer and Splunk's indexer) competing for RAM and disk I/O on the
  same 6GB NAS isn't a realistic homelab constraint to design around; toggling gives each stack
  its full resource budget instead.
- **A shared docker-compose.yml with Compose profiles** — rejected. Profiles solve toggling
  services *within* one compose file. Since Splunk and Wazuh live in separate repos with
  separate compose files, `docker compose up` / `down` in the relevant directory already
  provides the toggle without added complexity.
- **Splunk Enterprise Trial / paid tier** — not pursued for this phase. Splunk Free is
  sufficient to validate the pipeline and input sources at homelab scale.

## Architecture

- **Host**: Synology DS224+ (6GB RAM), Docker Compose via Container Manager
- **Container**: single `splunk/splunk` instance (indexer + search head + Splunk Web, combined
  single-instance deployment)
- **Memory**: explicit `mem_limit` set in `docker-compose.yml` rather than relying on default
  JVM-style sizing, so a single-instance deploy can't crowd out DSM and the always-on
  Grafana/Loki/Prometheus/Alloy stack
- **Ingestion paths**:
  - HTTP Event Collector (HEC), port 8088
  - Syslog, port 6514/udp (514/udp is already bound by the Alloy telemetry container on this host)
  - Forwarder-to-indexer receiving, port 9997

### Input sources

| Source | Path |
|---|---|
| OPNsense firewall/DNS logs | Remote syslog → 6514/udp |
| Unbound resolver logs | Remote syslog → 6514/udp |
| Wazuh alerts | Wazuh integrations/webhook → HEC |
| Synology DSM system logs | Control Panel > Log Center → syslog |
| Suricata IDS alerts (eve.json) | File monitor input |
| Docker container logs | Splunk Docker logging driver |

## Setup

```bash
cp .env.example .env    # fill in SPLUNK_PASSWORD and SPLUNK_HEC_TOKEN
docker compose up -d
```

Splunk Web is available at `http://<NAS-IP>:8000` after startup.

## Resource notes

- **Splunk Free's license caps ingestion at 500 MB/day** — exceeding it doesn't halt
  indexing immediately, it logs a license violation warning; search is disabled only
  after repeated violations accumulate in a rolling 30-day window (indexing continues
  throughout). Worth sizing input sources against this ceiling before wiring up all six
  planned sources — Suricata and Wazuh alerts (if/when enabled) are the sources most
  likely to be volume-heavy relative to it; OPNsense/Unbound syslog and DSM system logs
  are comparatively light. `Settings > Licensing > Usage Report` (or
  `index=_internal source=*license_usage.log* | stats sum(b) by index`) shows actual
  daily consumption once sources are flowing.
- Image is pinned to `splunk/splunk:10.4.3` rather than `:latest` — see Non-obvious
  findings below for why an unpinned tag silently broke a routine restart on this hardware.
- `mem_limit: 3g` / `mem_reservation: 1g` set in `docker-compose.yml`, sized against a 6GB
  NAS with Wazuh's indexer stopped. Re-check DSM Resource Monitor before adjusting.
- `cpus` (hard CPU quota) is unsupported on this DSM kernel — CFS bandwidth control isn't
  compiled in, so Docker's `NanoCPUs` mechanism fails outright. `cpu_shares: 512` is used
  instead — a relative weight (half the default 1024), deprioritizing Splunk below the
  always-on observability stack under contention. It has no effect unless the CPU is
  actually contended.
- Syslog input is mapped to host port `6514/udp` rather than the standard 514, since
  514/udp is already bound by the Alloy container on this host. Syslog sources pointed at
  Splunk directly need to target 6514.
- Config and indexed data are bind-mounted to `/volume1/docker/splunk/{etc,var}` rather
  than named Docker volumes. DSM's ACLs on Btrfs shares override POSIX mode bits even when
  `ls -l` shows `777` — the container's internal UID isn't a real DSM identity, so it falls
  through to the "Everyone" ACL entry, which defaults to read/execute only. Granting
  "Everyone: Read & Write" on the share (recursively) was required before first boot would
  succeed.
- Toggle procedure: stop Wazuh's indexer container before bringing Splunk up, or vice versa.

## Security considerations

- **"Everyone: Read & Write" ACL on the `docker` share's `splunk/etc` and `splunk/var`
  directories** (see Resource notes above) is a broader grant than ideal. "Everyone" in
  DSM's ACL model means every account defined on this NAS, not the public internet — the
  share isn't internet-exposed — but within that boundary, any DSM account with access to
  the `docker` share can write into `etc/apps/`, which Splunk's Ansible provisioning
  executes on start. That's a real path to code execution inside the container, not just
  config tampering, for a single-admin homelab where the practical risk is low but not zero.
- **Root-cause fix considered and rejected**: Splunk's Docker image supports `SPLUNK_USER`/
  `SPLUNK_GROUP` env vars to override which account its processes run as (default: the
  built-in `splunk` user, UID/GID `41812`), which in theory could map the container to a
  real DSM identity and let the ACL grant be narrowed back down. Rejected after checking
  Splunk's own docs and a documented GitHub issue: these variables are built around three
  specific sanctioned accounts (`splunk`, `ansible`, `root`), not arbitrary host UIDs.
  Pointing them at a DSM UID like `synadmin`'s (1026) is unsupported territory, with a real
  precedent of it breaking the container's internal auth/config generation (corrupted
  `passwd` file, failed HEC setup) even when overriding to one of the three sanctioned
  accounts. Left as a known, documented tradeoff rather than "fixed."

## Non-obvious findings

- **`splunk/splunk:latest` is unsafe to run unpinned on this hardware.** A `docker compose
  down`/`up` cycle — done here to pick up an unrelated port-mapping fix — triggered Splunk's
  upgrade-migration path because the image behind `:latest` had silently become a newer
  version (`10.4.3`) than what was recorded in the bind-mounted config, sometime after
  initial deployment. That migration path runs its own CPU precheck requiring AVX, separate
  from and stricter than the KV Store/MongoDB AVX requirement above — it hard-fails the
  entire Splunk binary, not just KV Store, and crash-loops the container indefinitely.
  Confirmed via `docker exec splunk /opt/splunk/bin/splunk version` and image label
  inspection that `10.4.3` was already fully downloaded and cached locally before this was
  ever noticed — the mismatch between cached image and on-disk config state was dormant and
  invisible the entire time Splunk kept running continuously, only surfacing on restart.
  Fixed by wiping `etc/`/`var/` for a genuinely fresh install (sidesteps the
  upgrade-detection path entirely) and pinning `image: splunk/splunk:10.4.3` explicitly in
  `docker-compose.yml` instead of `:latest`, so a future restart can't silently pull a
  version this hardware can't run.
- **KV Store cannot run on this hardware — confirmed, permanent limitation, not a
  misconfiguration.** Splunk Web showed `KV Store process terminated abnormally (exit code
  4, status PID ... killed by signal 4: Illegal instruction)` shortly after first boot.
  Splunk's KV Store is backed by MongoDB internally, and modern `mongod` builds require the
  AVX CPU instruction set to run at all — crashing with `SIGILL` if it's absent. Confirmed
  via `cat /proc/cpuinfo | grep avx` on the DS224+: no AVX flag present anywhere in the
  Celeron J4125's (Gemini Lake) flag set. No fix exists short of different hardware. Core
  functionality (indexing, search, HEC ingestion) doesn't depend on KV Store; what's lost
  is KV Store-backed app config storage, Distributed Configuration Management, and parts of
  the Monitoring Console. Worth knowing for anyone running Splunk on similar low-power
  Celeron J-series NAS hardware.
- **The official Splunk Docker image runs a full Ansible playbook on every container
  start**, not a thin shell entrypoint. First boot works through roles like `splunk_common`
  and `splunk_standalone` — gathering facts, detecting cluster config, setting directory
  ownership, generating secrets, and templating `.conf` files — visible in
  `docker compose logs splunk`. Worth knowing when debugging startup issues: a failure
  during first boot is often an Ansible task failure (e.g. "Update Splunk directory owner"
  or the config-archive extraction step failing due to bind-mount permission mismatches),
  not a Splunk process crash.
- **License acceptance requires two separate flags, not one.** `SPLUNK_START_ARGS:
  --accept-license` alone isn't sufficient on current image versions — `SPLUNK_GENERAL_TERMS:
  --accept-sgt-current-at-splunk-com` is also required, or the container loops on a
  license-not-accepted message instead of starting.
