# Ubuntu RT Latency Reference

Source: https://documentation.ubuntu.com/real-time/latest/how-to/measure-maximum-latency/

Use this reference when explaining or adapting raw Ubuntu Real-time latency measurement workflows. In ServoBox work, prefer the project commands first, then use these details for interpretation, deeper troubleshooting, or manual reproduction.

## Core Concepts

- Maximum latency is the longest observed time for the system to respond to an event.
- Maximum latency is the main deadline-risk signal for RT workloads.
- `cyclictest` is the primary tool for measuring Linux real-time latency and is provided by the `rt-tests` package.
- `stress-ng` is useful for simulating production-like system load while measuring latency.
- The `Max` value in `cyclictest` output is the key value to inspect, reported per CPU.
- `cyclictest` reports microseconds by default; use `--nsecs` or `-N` for nanoseconds.

## ServoBox Defaults

For normal ServoBox validation, start with:

```bash
servobox rt-verify
servobox test --duration 30 --stress-ng
```

Use raw `cyclictest` commands when the user needs manual reproduction, comparison outside ServoBox, histogram data, or detailed interpretation of RT behavior.

## Install Tools

```bash
sudo apt install rt-tests
sudo apt install stress-ng
```

Install `gnuplot` only when histogram plotting is needed:

```bash
sudo apt install gnuplot
```

`cyclictest` must run as root, with `sudo`, or as a member of the `realtime` group.

## Basic Measurements

Run until interrupted:

```bash
sudo cyclictest
```

Run a fixed number of iterations:

```bash
sudo cyclictest --loops=100000
sudo cyclictest -l 100000
```

Run for a fixed duration:

```bash
sudo cyclictest --duration=10m
sudo cyclictest -D 10m
```

Duration suffixes include `m` for minutes, `h` for hours, and `d` for days.

Report in nanoseconds:

```bash
sudo cyclictest --nsecs
sudo cyclictest -N
```

## Comparing Runs

When comparing a standard kernel, RT kernel, different CPU isolation layouts, or different VM pinning plans:

- Keep duration or loop count fixed across runs.
- Keep load conditions fixed across runs.
- Record kernel version, CPU isolation, CPU governor, IRQ affinity, and VM pinning state.
- Compare per-CPU `Max` values, not only averages.
- Expect a correctly configured RT kernel to show smaller and more deterministic maximum latency on the same hardware.

## Histograms

`cyclictest` can emit latency histograms with `--histogram` or `-h`. Ubuntu's referenced helper workflow uses `-h400` and `-D1m`, then plots the transformed histogram with `gnuplot`.

The generated plot is useful for seeing distribution shape, outliers, and whether only one CPU is showing problematic latency.

## Production-Like Load

For more realistic latency measurements, run tests under the same or similar load expected in production. Ubuntu's example uses:

```bash
sudo stress-ng --cyclic 1 \
               --cyclic-dist 250 \
               --cyclic-method clock_ns \
               --cyclic-policy rr \
               -t 3600 \
               --log-file cyclic-stress.log \
               --verbose
```

Treat these `stress-ng` options as examples. Tune the stressors, duration, and scheduling policy to match the target workload.

## Interpretation Checklist

- If `Max` latency is high on all CPUs, inspect global host load, CPU governor, kernel boot parameters, and RT kernel status.
- If only specific CPUs show high `Max` latency, inspect CPU pinning, IRQ affinity, shared cache/NUMA topology, and whether housekeeping tasks are leaking onto isolated CPUs.
- If VM results are noisy, compare host and guest `cyclictest` results, then inspect libvirt `<vcpupin>`, `<emulatorpin>`, memory locking, ballooning, and CPU passthrough.
- If results improve only when idle, build a production-like `stress-ng` profile before judging readiness.
