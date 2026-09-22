# Splunk Docker Deployment

A standalone Splunk Enterprise 9.3.13 deployment on a Synology DS224+
using Docker Compose.

This document is limited to the Docker deployment itself. Project
rationale, the Terraform/KVM alternative, and shared goals are
documented in the [repository README](../README.md). Configuration
performed after Splunk is running belongs in
[post-deployment.md](../docs/post-deployment.md).

## Architecture

- **Host:** Synology DS224+ with 6 GB RAM, Docker Compose via
  Container Manager
- **Splunk version:** `9.3.13`
- **Container:** single `splunk/splunk` instance providing the
  indexer, search head, and Splunk Web
- **Persistence:** Docker-managed named volumes for `/opt/splunk/etc`
  and `/opt/splunk/var`
- **Memory:** `mem_limit: 3g` and `mem_reservation: 1g`
- **CPU scheduling:** `cpu_shares: 512`
- **Network:** dedicated Docker bridge network
- **Published ports:**
  -   `8000/tcp` — Splunk Web
  -   `8088/tcp` — HTTP Event Collector (HEC)
  -   `9997/tcp` — Splunk TCP receiver
  -   `6514/tcp` — reserved for the planned syslog input

Splunk 9.3.13 is intentionally pinned for the Synology deployment. The
Terraform/KVM deployment uses Splunk 10.4.3 on hardware/virtualization
that can provide the CPU capabilities required by that release.

## Persistence design

The deployment uses Docker-managed named volumes:

```yaml
volumes:
  - splunk-config:/opt/splunk/etc
  - splunk-data:/opt/splunk/var
```

Earlier iterations used Synology bind mounts for these paths. That
introduced DSM ACL and container UID/GID interactions during Splunk's
Ansible provisioning.

Named volumes allow the container to establish and maintain the
ownership and permissions expected inside `/opt/splunk` without
requiring broad DSM ACL changes. They also keep Splunk configuration and
indexed data persistent across container removal and recreation.

This is an intentional design decision rather than an incidental Docker
default.

## Setup

Create the local environment file from the example:

```bash
cp .env.example .env
```

Populate `SPLUNK_PASSWORD` and `SPLUNK_HEC_TOKEN` locally. Do not commit
the `.env` file.

Validate the Compose configuration:

```bash
docker compose config --quiet
```

Pull the pinned image:

```bash
docker compose pull
```

Start Splunk:

```bash
docker compose up -d
```

Watch first-run provisioning:

```bash
docker compose logs -f splunk
```

The official image runs an Ansible provisioning playbook before
streaming `splunkd_stderr.log`. A successful run ends with a play recap
showing `failed=0`.

Splunk Web is then available at:

```text
http://<NAS-IP>:8000
```

The initial username is `admin`; the password is the value supplied
through `SPLUNK_PASSWORD`.

## Validation

Check the installed version as the Splunk user:

```bash
docker exec -u splunk splunk /opt/splunk/bin/splunk version
```

Validated result:

```text
Splunk 9.3.13 (build 688758e24bbe)
```

Check service status:

```bash
docker exec -u splunk splunk /opt/splunk/bin/splunk status
```

A healthy instance reports that `splunkd` and its helper processes are
running.

Running the CLI without `-u splunk` can produce permission errors for
files under `/opt/splunk/var`. Those errors do not by themselves
indicate that `splunkd` has failed.

## Lifecycle and persistence validation

The deployment has been tested through three lifecycle cases.

### Fresh provisioning

A clean deployment with newly created named volumes completed the
Docker-Splunk Ansible playbook with `failed=0`, started `splunkd`, and
allowed successful Splunk Web login.

### Container restart

```bash
docker compose restart splunk
```

Splunk reprovisioned normally and returned to service with the persisted
configuration intact.

### Container removal and recreation

```bash
docker compose down
docker volume ls | grep splunk
docker compose up -d
```

Plain `docker compose down` removes the container and Compose network
but preserves the named volumes. A new 9.3.13 container successfully
attached to the existing `splunk-config` and `splunk-data` volumes,
completed provisioning with `failed=0`, and returned to service.

Do not add `-v` to `docker compose down` unless the intent is to delete
the persistent Splunk configuration and indexed data.

## Resource notes

- `mem_limit: 3g` and `mem_reservation: 1g` are sized against a 6 GB
  NAS with Wazuh's indexer stopped. Re-check DSM Resource Monitor
  before changing them.
- A hard `cpus` quota is unsupported on this DSM kernel because the
  required CFS bandwidth control is not available. `cpu_shares: 512`
  is used instead. This is a relative scheduling weight and matters
  only when CPU is contended.
- Splunk and Wazuh's indexer are toggled rather than run concurrently
  on the NAS so each indexing workload has the available resource
  budget.
- Port `6514/tcp` is published by the current Compose configuration.
  The actual syslog input and source configuration are post-deployment
  concerns and should be documented in `docs/post-deployment.md`.

## Security considerations

- Secrets are supplied through environment-variable substitution from
  the local `.env` file rather than embedded in `compose.yml`.
- The `.env` file contains live credentials and should remain local
  and uncommitted.
- Docker-managed named volumes avoid the broad Synology
  `"Everyone: Read & Write"` ACL that was required by the earlier
  bind-mount design.
- Splunk's persistent configuration and data remain inside
  Docker-managed volumes; normal `docker compose down` does not remove
  them.

## Non-obvious findings

### Pin the Splunk image version

Do not use `splunk/splunk:latest` for this deployment. A floating tag
can change the Splunk version used the next time a container is
recreated, turning a routine lifecycle operation into an unintended
version transition.

The Synology deployment is therefore pinned to:

```yaml
image: splunk/splunk:9.3.13
```

Version changes should be explicit and tested.

### Splunk 10.x is not the Docker target on this NAS

Testing with newer Splunk images exposed CPU compatibility problems on
the DS224+. Splunk 10.4.3 is therefore used by the separate
Terraform/KVM deployment, while the Synology Docker path remains on
9.3.13.

This distinction is deliberate: the two deployment methods do not need
to use the same Splunk release in order to target equivalent
post-deployment functionality.

### KV Store operates under Splunk 9.3.13

The DS224+'s Intel Celeron J4125 does not provide AVX. Testing with newer
Splunk releases exposed CPU compatibility problems, including failures in
components that require newer CPU instruction sets.

Under Splunk Enterprise 9.3.13, however, the KV Store's `mongod` process has
been verified running successfully on this hardware:

```text
mongod --dbpath=/opt/splunk/var/lib/splunk/kvstore/mongo ...
```

### Named volumes materially simplify Splunk provisioning

Splunk's official Docker image performs a full Ansible provisioning run
at startup. That process manages ownership, secrets, configuration
files, HEC, receiver settings, and other state under `/opt/splunk`.

Using Docker-managed named volumes allows that provisioning process to
manage the filesystem as expected. Earlier bind-mounted storage
introduced Synology ACL and container UID/GID complications.

### Ansible checks for an existing installation on normal starts

When persistent volumes already contain Splunk state, startup logs
include tasks such as:

```text
Check for existing installation
Set current version fact
Setting upgrade fact
```

These task names do not mean an upgrade is actually being performed. A
container recreation using the existing 9.3.13 volumes produced these
same tasks and subsequently completed with `failed=0`.

The play recap and subsequent Splunk service state are the useful
indicators of success or failure.

### Run Splunk CLI commands as the Splunk user

For administrative checks inside the container, use:

```bash
docker exec -u splunk splunk /opt/splunk/bin/splunk <command>
```

Running the CLI as the container's default exec user can produce
permission errors for Splunk runtime and log paths.

### License acceptance is version-specific

The 9.3.13 deployment uses:

```yaml
SPLUNK_START_ARGS: --accept-license
```

The additional general-terms acceptance setting encountered with newer
Splunk Docker images is not part of this 9.3.13 Compose configuration.
Treat license acceptance requirements as image-version-specific rather
than assuming the same environment variables apply across 9.x and 10.x.

## Post-deployment configuration

This README ends when the Docker deployment is installed, persistent,
and accessible.

Indexes, inputs, HEC usage, syslog sources, sourcetypes, retention,
validation searches, and other shared Splunk configuration should be
documented in:

[Post-deployment configuration](../docs/post-deployment.md)

That document is intended to define a common functional end state for
both:

- Docker/Synology — Splunk Enterprise 9.3.13
- Terraform/KVM — Splunk Enterprise 10.4.3

Where the versions or deployment methods differ, the post-deployment
guide should document the implementation-specific procedure explicitly.
