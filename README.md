# speedtest-hexs-armv5

Ookla **Speedtest CLI** packaged for the **MikroTik hEX S** (RouterOS, ARM 32-bit) as a
`linux/arm/v5` container, so the router can run a periodic WAN speedtest itself and push
the result to InfluxDB → Grafana.

Sibling of [`cloudflared-hexs-armv5`](https://github.com/bossoq/cloudflared-hexs-armv5):
same board, same reason it must be **arm/v5 soft-float** — the hard-float `armhf` Ookla
build SIGILLs on the EN7562CT, the `armel` (soft-float, static musl) build runs clean
(`cloudflared-linux-arm` taught us the same lesson).

## Image

`ghcr.io/bossoq/speedtest-hexs-armv5:latest`

- Base: `arm32v5/busybox:1.37.0-uclibc` (static) + CA certs + the static `armel` Ookla binary.
- Entrypoint `entrypoint.sh` loops: run `speedtest --format=json` → parse → POST InfluxDB 2
  line protocol → `sleep $INTERVAL`. Measurement `speedtest`, tags `site`,`source`,`server_id`,
  fields `download_mbps`,`upload_mbps`,`ping_ms`,`jitter_ms`,`packet_loss`.

### Runtime env

| var | default | notes |
|-----|---------|-------|
| `INFLUX_URL` | *(required)* | e.g. `http://10.0.1.108:8086` |
| `INFLUX_TOKEN` | *(required)* | write-scoped token for the bucket |
| `INFLUX_ORG` | `Picturous` | |
| `INFLUX_BUCKET` | `Proxmox` | |
| `SITE` | `nongkhaem` | tag |
| `SOURCE` | `mikrotik` | tag (distinguishes from the CT108 host collector) |
| `SERVER_ID` | `16063` | pin the same Ookla server the host collector uses |
| `INTERVAL` | `21600` | seconds between runs (6h) |

> **Note on accuracy:** a speedtest *inside* a container on the hEX S is CPU-bound (no
> hardware fast-path for locally-originated traffic) and reads ~70% of a ~1 Gbps link
> (~650/595 vs ~922/759 measured). It is an *effective-throughput* trend, not a capacity
> measurement — run it **alongside** the host-side collector, not as a replacement.

## RouterOS deploy

```
/container/config/set registry-url=https://ghcr.io tmpdir=pull
/container/envs/add list=st-env key=INFLUX_URL value=http://10.0.1.108:8086
/container/envs/add list=st-env key=INFLUX_TOKEN value=<write-token>
/interface/veth/add name=veth-st address=10.0.1.6/16 gateway=10.0.1.101
/interface/bridge/port/add bridge=bridge interface=veth-st
/container/add remote-image=bossoq/speedtest-hexs-armv5:latest interface=veth-st \
  root-dir=st envlist=st-env dns=1.1.1.1 logging=yes start-on-boot=yes
```

## Build

GitHub Actions (`.github/workflows/build.yml`, `runs-on: ubuntu-latest`) cross-builds
`linux/arm/v5` (no QEMU: fetch stage is amd64, final stage has no `RUN`) and pushes to GHCR.
Triggers: `workflow_dispatch` (optional `st_version`), push to the build files, weekly cron.
Make the GHCR package **public** for anonymous `remote-image` pulls from the router, or set
`/container/config username=<gh> password=<read:packages PAT>`.
