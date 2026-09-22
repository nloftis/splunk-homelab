# Post-Deployment Configuration

This document records configuration performed after Splunk Enterprise has
been deployed and validated.

The deployment-specific guides establish the Splunk platform itself. The
procedures here configure data collection, ingestion, and validation so the
homelab can use Splunk with real network and security telemetry.

Where the Docker Compose and Terraform/KVM deployments require different
procedures, those differences should be identified explicitly while preserving
the same intended functional end state.

## Windows 11 Universal Forwarder

The first endpoint configured for Splunk ingestion is the Windows 11 VM. The
endpoint also runs a Wazuh agent, allowing telemetry from the same system to be
examined through both platforms.

The validated Splunk path is:

```text
Windows 11
    |
    | Splunk Universal Forwarder
    | TCP 9997
    v
Splunk Enterprise
```

The current Terraform/KVM Splunk Enterprise instance is used as the receiving
indexer for this configuration.

### Configure the receiving port

Before installing the Universal Forwarder, configure Splunk Enterprise to
accept forwarded data.

In Splunk Web, navigate to:

```text
Settings
  -> Forwarding and receiving
     -> Receive data
        -> Configure receiving
           -> New Receiving Port
```

Configure:

| Setting | Value |
|---|---|
| Receiving port | `9997/TCP` |

The validated Terraform/KVM Splunk VM address at the time of configuration was
`192.168.10.12`.

### Verify connectivity

From the Windows 11 endpoint, verify that Splunk Web is reachable:

```powershell
Test-NetConnection 192.168.10.12 -Port 8000
```

Then verify the receiving port:

```powershell
Test-NetConnection 192.168.10.12 -Port 9997
```

Both tests should report:

```text
TcpTestSucceeded : True
```

The Windows 11 VM and Splunk VM currently reside on the same
`192.168.10.0/24` network, so communication between the two systems does not
traverse the OPNsense firewall.

### Install the Universal Forwarder

Install Splunk Universal Forwarder 10.4.3 for Windows x64 using the MSI
installer.

The validated installer configuration is:

| Setting | Value |
|---|---|
| Universal Forwarder version | 10.4.3 |
| Platform | Windows 11 x64 |
| Splunk environment | On-premises Splunk Enterprise |
| Installation path | `C:\Program Files\SplunkUniversalForwarder\` |
| Service account | Splunk Virtual Account |
| `SeBackupPrivilege` | Enabled |
| `SeSecurityPrivilege` | Enabled |
| Performance Monitor Users | Enabled |
| Application Event Log | Enabled |
| Security Event Log | Enabled |
| System Event Log | Enabled |
| Forwarded Events Log | Disabled |
| Setup Log | Disabled |
| Active Directory monitoring | Disabled |
| Performance monitoring | Disabled |
| File/directory monitoring | None |
| Universal Forwarder administrator | `admin` |
| Administrator password | Installer-generated random password |
| Deployment Server | None |
| Receiving Indexer | `192.168.10.12` |
| Receiving Port | `9997` |
| Custom TLS certificate | None; default Splunk certificate |

Only the Application, Security, and System Windows Event Logs are enabled for
the initial configuration. This provides a controlled Windows event baseline
before additional telemetry sources are introduced.

A deployment server is not configured. The homelab currently has a small
number of forwarders, so centralized forwarder configuration management is not
required for the initial deployment.

### Verify the Universal Forwarder service

After installation, open PowerShell and verify the Windows service:

```powershell
Get-Service SplunkForwarder
```

The validated installation reported:

```text
Status   Name               DisplayName
------   ----               -----------
Running  SplunkForwarder    SplunkForwarder
```

A `Running` status confirms that the Universal Forwarder service is active.

### Verify event ingestion

Open **Search & Reporting** in Splunk Web.

For the initial ingestion check, search recent indexed events:

```spl
index=* earliest=-15m
```

The validated Windows Universal Forwarder installation returned indexed data
with this search.

To identify the hosts, sources, and sourcetypes represented in the received
events, use:

```spl
index=* earliest=-15m
| stats count by host source sourcetype
```

This query provides an inventory of the event streams reaching Splunk and is
useful when validating new data sources.

### Validation status

The Windows 11 Universal Forwarder path has been validated end to end:

```text
Windows Event Logs
    |
    +-- Application
    +-- Security
    +-- System
    |
    v
Splunk Universal Forwarder 10.4.3
    |
    | TCP 9997
    v
Splunk Enterprise 10.4.3
    |
    v
Indexed and searchable
```

At this stage, the Windows endpoint provides the first common endpoint for the
Splunk and Wazuh environments. Additional telemetry should be introduced
incrementally so collection and analysis behavior can be compared without
obscuring the initial baseline.

## OPNsense Syslog

OPNsense provides firewall and network telemetry to Splunk using an RFC5424 remote syslog destination. The validated Splunk VM destination is `192.168.10.12` on TCP port `6514`.

### Configure the Splunk index and TCP input

A dedicated `opnsense` index was created in Splunk. The validated TCP input uses port `6514`, no source-name override, `Restrict to Host` = `192.168.10.1`, sourcetype `syslog`, host method IP, and index `opnsense`. Port `6514` is plain TCP in this configuration; TLS was not configured.

### Configure the OPNsense remote syslog destination

The validated OPNsense destination is enabled with transport `TCP(4)`, destination `192.168.10.12`, port `6514`, RFC5424 enabled, description `Splunk Telemetry`, and levels `info`, `notice`, `warn`, `error`, `critical`, `alert`, and `emergency`. No facilities were explicitly selected. The configured applications include the firewall/filter logging sources used by the homelab.

### Verify the listener and troubleshoot the source address

Because the Splunk VM uses macvtap networking, administrative shell access from the Pop!_OS KVM host uses:

```bash
virsh console splunk
```

Verify the listener:

```bash
sudo ss -lntp | grep 6514
```

The validated listener reported:

```text
LISTEN 0      128          0.0.0.0:6514       0.0.0.0:*    users:(("splunkd",pid=709,fd=125))
```

The first TCP input incorrectly restricted the sender to `192.168.1.1`, the normal OPNsense management address. Splunk listened successfully but indexed no events. OPNsense **Interfaces -> Diagnostics -> Port Probe** successfully connected to `192.168.10.12:6514`, proving the network path and listener were reachable.

Packet capture then identified the actual TCP peer:

```bash
sudo tcpdump -ni any tcp port 6514
```

OPNsense-originated traffic toward the PC subnet was sourced from `192.168.10.1`, its interface on `192.168.10.0/24`. With the incorrect restriction, packet capture showed TCP setup followed by Splunk closing/resetting the connection. Splunk Web did not expose the host-restriction field when editing the existing input, so the input was deleted and recreated with `Restrict to Host: 192.168.10.1`. Sustained syslog traffic and indexed events followed.

### Verify OPNsense ingestion

```spl
index=opnsense earliest=-15m
```

```spl
index=opnsense earliest=-15m
| stats count by host source sourcetype
```

The validated metadata is `host=OPNsense.home.arpa`, `source=tcp:6514`, and `sourcetype=syslog`. The TCP peer `192.168.10.1` and indexed hostname `OPNsense.home.arpa` describe different layers and are not contradictory. Raw RFC5424 `filterlog` events arrived with correct event boundaries and timestamps, including the `-10:00` offset.

## Pop!_OS Linux Universal Forwarder

A Pop!_OS 24.04 (COSMIC) VM is used as the Linux endpoint for the Splunk comparison. This avoids the macvtap host-to-guest limitation between the physical Pop!_OS KVM host and the Splunk VM while retaining a representative Linux workstation source.

### Place the Linux VM on the PC network

The Cosmic VM was initially attached to libvirt's default NAT network at `192.168.122.76/24`, from which it could not reach the Splunk VM. In virt-manager its NIC was changed to a **Macvtap device** on `enp4s0`, retaining the `virtio` device model. After reboot, Cosmic received `192.168.10.16/24`.

Connectivity was verified with:

```bash
ping 192.168.10.12
nc -vz 192.168.10.12 9997
```

The TCP test succeeded, preserving the existing Splunk VM networking without adding a second interface.

### Install and initialize Universal Forwarder

The VM reports `amd64` from `dpkg --print-architecture`. Splunk Universal Forwarder 10.4.3 for Linux AMD64 was installed under `/opt/splunkforwarder`. Version verification reported:

```text
Splunk Universal Forwarder 10.4.3 (build 4174a2deda5d)
```

The relevant local accounts are:

| Purpose | Account |
|---|---|
| Universal Forwarder administrator | `splunkadmin` |
| systemd/service account | `splunkfwd` |

The administrator password is intentionally not documented. The package created a systemd unit configured to run Splunk as `splunkfwd`.

A recurring `sudo: unable to resolve host pop-os` message was observed. This is a separate local hostname-resolution issue and did not prevent UF installation, startup, forwarding, or log collection.

Start and verify the forwarder:

```bash
sudo /opt/splunkforwarder/bin/splunk start
sudo /opt/splunkforwarder/bin/splunk status
```

### Configure and verify forwarding

```bash
sudo /opt/splunkforwarder/bin/splunk add forward-server 192.168.10.12:9997
sudo /opt/splunkforwarder/bin/splunk list forward-server
```

The validated state was:

```text
Active forwards:
    192.168.10.12:9997

Configured but inactive forwards:
    None
```

### Grant the service account access to system logs

The initial baseline uses `/var/log/auth.log` and `/var/log/syslog`. Both are group-readable by `adm`, while `splunkfwd` initially belonged only to its own group. Rather than weakening log permissions, add the service account to `adm` and restart the forwarder:

```bash
sudo usermod -aG adm splunkfwd
sudo /opt/splunkforwarder/bin/splunk restart
id splunkfwd
```

The validated membership included `groups=1001(splunkfwd),4(adm)`. Actual access was verified as the service account:

```bash
sudo -u splunkfwd head -n 3 /var/log/auth.log
sudo -u splunkfwd head -n 3 /var/log/syslog
```

Both returned records without permission errors.

### Configure Linux log monitors

```bash
sudo /opt/splunkforwarder/bin/splunk add monitor /var/log/auth.log \
  -sourcetype linux_secure

sudo /opt/splunkforwarder/bin/splunk add monitor /var/log/syslog \
  -sourcetype syslog
```

No dedicated Linux index was specified for this initial controlled baseline.

### Verify Linux ingestion

```spl
index=* host="pop-os"
```

The validated events showed current timestamps and sensible event boundaries, including sudo/PAM authentication activity and ordinary system messages.

Inventory the streams with:

```spl
index=* host="pop-os"
| stats count by host source sourcetype
```

The validated mapping is:

| Host | Source | Sourcetype |
|---|---|---|
| `pop-os` | `/var/log/auth.log` | `linux_secure` |
| `pop-os` | `/var/log/syslog` | `syslog` |

Event counts are not treated as fixed expected values because they change continuously.

The Pop!_OS path is validated end to end:

```text
Pop!_OS 24.04 VM
    |
    +-- /var/log/auth.log  -> linux_secure
    +-- /var/log/syslog    -> syslog
    |
    v
Splunk Universal Forwarder 10.4.3
    |
    | TCP 9997
    v
Splunk Enterprise 10.4.3
    |
    v
Indexed and searchable
```

At this point Splunk has validated telemetry paths for Windows 11, OPNsense, and a Pop!_OS Linux endpoint. These sources form the basis for the subsequent Splunk-versus-Wazuh comparison.
