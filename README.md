# servburn

A burn-in and stress test suite for Linux servers, built to replace PassMark
BurnInTest in a fleet that mostly runs on live machines. One native binary
with a desktop window when there is a display and a terminal mode when there
isn't; packaged as RPM, DEB and tarball; nothing to install beyond the package.

```
curl -fsSL https://raw.githubusercontent.com/ezClap/scripts/main/install.sh | sudo sh
servburn                    # opens the window (console, or ssh -X)
servburn --headless -d 30m  # or the terminal version, same engine, same reports
```

## What it tests

Every test **verifies its results** against a reference computed on the same
machine before the load started. Throughput numbers tell you the machine is
fast; verification tells you it is *correct*, and that is what a burn-in is for.

| Test | Load | What a failure looks like |
|---|---|---|
| **CPU** | ten kernels per core: SHA-256 / SHA-512 / BLAKE2b / MD5 hashing, CRC32, deflate round-trip, a float64 series, a dense 128x128 float64 matrix multiply, a prime sieve to 2,000,000 and a 61-bit integer chain. Compiled code, so SHA-NI, AVX2/AVX-512 and FMA are reached directly; the report names the extensions the machine has | any kernel returning a different answer - silent data corruption |
| **Memory** | zeros / ones / 55AA / AA55 / random / address patterns written and read back through a large allocation | a byte that comes back different, reported with pattern and offset |
| **Disk** | 4 MiB blocks carrying their index and a CRC, written, fsynced, evicted from the page cache, then re-read sequentially and again in butterfly seek order | a CRC mismatch, a misplaced block, or an I/O error |
| **2D graphics** | fills, unaligned blits, a whole-surface alpha blend and a large scroll over a 1024x576 framebuffer in memory | a frame whose hash differs - a wrong pixel |
| **3D graphics** | a full software pipeline: transform, perspective projection, backface culling, depth sort, flat shading and scanline rasterisation of a 2,464-triangle mesh | a frame that renders differently than it did before the load |
| **Network** | 1 MiB TCP blocks, CRC-checked by the far end and echoed back; loopback, or a second machine running `servburn --net-server` | a corrupted block or a dropped connection |
| **GPU** | repeated matrix products compared element-wise (CuPy / PyTorch / gpu-burn, whichever is present); monitored via nvidia-smi / rocm-smi either way | any element that differs between passes |

Watched throughout: every hwmon / thermal-zone temperature (against the
vendor's own critical trip point where the kernel exposes it), core clocks,
RAPL package power, fan speeds, CPU thermal-throttle counters, EDAC ECC
counters, and - snapshotted before and after - SMART attributes and the kernel
error log. Anything that moves in the wrong direction is a finding.

Output: the window (or terminal progress lines), a standalone HTML report with
charts, and a JSON file with every sample.

## The window

Tick the tests, pick a profile, set the knobs, press **Start**. The right-hand
side shows exactly what would run on this machine - cores, memory, the scratch
file and its filesystem, what will be watched - and the equivalent command line,
so a run set up by hand can be copied into cron or a provisioning script.

While it runs: a live table per test (rate, total, errors, state), temperature
and throughput plots, the system line and the log. **Stop** ends the run
cleanly and still writes the report. At the end: PASS / WARN / FAIL with the
findings, per-test figures, and a button that opens the HTML report.

## Safe on a live box

The defaults assume the machine has a job to do:

- one core is left alone, workers are niced, the disk test runs at low I/O priority
- memory is sized from `MemAvailable`, never from total, and a floor is always
  left free; if the system gets tight mid-run the worker releases its block and
  waits rather than letting the OOM killer pick a victim
- the disk test writes **one scratch file** in a directory you name and deletes
  it afterwards. It refuses a path that is not a writable directory and never
  opens a block device
- if any sensor passes its limit the run aborts on its own
- Ctrl-C, SIGTERM or the Stop button stop cleanly and still produce the report

| | `safe` | `standard` (default) | `burnin` |
|---|---|---|---|
| duty cycle | 60% | 100% | 100% |
| cores | all but a quarter | all but one | all |
| memory | 25% of available, 4 GB floor | 50%, 2 GB floor | 85%, 1 GB floor |
| disk | 5% of free, idle I/O | 4 GB, low I/O | 16 GB, normal I/O |
| graphics workers | 1 | 1 | 2 |
| nice | +15 | +10 | 0 |

`safe` is for a machine under load right now; `burnin` is for hardware that is
out of service.

## Terminal use

```bash
servburn --preflight                              # print the plan, change nothing
servburn --headless -d 30m                        # standard profile, confirm, run
servburn --headless -p safe -d 4h -y -o /var/log/burnin
servburn --headless -p burnin -d 12h -y           # acceptance test on new hardware
servburn --headless -t cpu,memory,2d,3d -d 1h -y  # just the parts you care about
servburn --autostart -d 2h                        # open the window and begin at once
servburn --net-server                             # on host B, then on host A:
servburn --headless -t net --net-peer hostB:9977 -d 1h -y
```

Exit codes: **0** pass, **1** failure (errors found), **2** warnings only,
**3** could not start. So from a provisioning script:

```bash
servburn --headless -p burnin -d 6h -y -o /var/log/burnin || \
  echo "$(hostname) failed burn-in" | mail -s burn-in ops@example.com
```

`servburn --help` lists every knob (workers, sizes, floors, ports, limits).

## Reading the result

- **FAIL** - a verification error, a SMART or ECC counter that moved, a new
  machine-check or I/O error in the kernel log, or a temperature limit passed.
  Do not put the machine into service.
- **WARN** - nothing corrupted, but something to look at: thermal throttling
  (the machine could not hold its clocks), a correctable ECC error, a worker
  that stopped making progress.
- **PASS** - everything checked came back correct and nothing moved.

A clean pass is evidence about the hours you ran. For new hardware 8-24 hours
is the usual bar; for a machine that has been acting up, run it until it
misbehaves.

## Compared with BurnInTest

| BurnInTest | servburn |
|---|---|
| CPU maths, primes, matrix, float, compression, encryption, extended instructions | `cpu`, all verified; SIMD reached through compiled hashing and the vectorised matrix multiply |
| RAM | `memory`, with a live-system floor BurnInTest has no equivalent of |
| Disk incl. butterfly seek | `disk` |
| 2D / 3D graphics | rendered into memory (a server has no windowing system to draw on); every frame verified. A real GL renderer can be driven instead with `--gfx3d-cmd`, at the cost of verification |
| Network | `net`, with a real peer mode |
| Temperature / max temperature | continuous, with automatic abort and the vendor's trip points |
| SMART, ECC, MCE | diffed across the run - BurnInTest reports them, it does not diff them |
| Optical, USB loopback, serial/parallel loopback, sound, webcam, printer, tape | **not covered** - they need physical hardware or a loopback plug that rack servers do not have |

## Installing

One line on any server:

```bash
curl -fsSL https://raw.githubusercontent.com/ezClap/scripts/main/install.sh | sudo sh
```

To install and open the window in one go, append `&& servburn`.

The installer picks the package that fits the machine - the RPM on
dnf / yum / zypper systems, the DEB on apt systems, the tarball under
`/usr/local` elsewhere - downloads it from the same repo folder it came from,
and installs the window's runtime libraries from the distribution's own
repositories (X11, xkbcommon, Mesa with its software GL driver, xauth for
`ssh -X`) plus `smartmontools`. Afterwards it runs `servburn --check`, which
lists what the machine has and lacks with the exact package names to install
if anything is still missing. `SERVBURN_HEADLESS_ONLY=1` skips the window's
libraries on a box that will only ever run the terminal mode. Without network access, download the RPM (or DEB) and install it
directly: `sudo dnf install ./servburn-2.0.0-1.x86_64.rpm`. If the files are
hosted somewhere else, point the installer there with
`SERVBURN_URL=https://... sudo -E sh install.sh`.

The binary is linked against glibc 2.28, so one package covers RHEL / Rocky /
Alma 8 and newer, Debian 10+, Ubuntu 18.10+ and SUSE 15+. The window needs
X11 or Wayland and libGL (software rendering through llvmpipe is fine - that is
what it uses over `ssh -X`); the headless mode needs nothing else at all.

## Building from source

```bash
cargo build --release                       # needs Rust 1.75+
sh packaging/build-packages.sh              # binary + RPM + DEB + tarball into dist/
```

For a binary that runs on older distributions than the build machine, install
`cargo-zigbuild` and `zig` (`pip install ziglang` provides one); the build
script uses them automatically.
