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

## Non-obvious findings

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
