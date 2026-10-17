"""SIMULATED vehicle passes through a fixed-time signal, for testing the learner only (C8).

Everything produced here is synthetic. None of it describes a real Chennai signal, and no number from it may be reported as a finding
about Chennai. The kinematics are deliberately simple: cruise, brake at a constant rate to the back of the queue, wait for green plus a
start-up delay per queued car, accelerate at a constant rate back to cruise. GPS position noise is Gaussian, sampled at 1 Hz.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ml.signal_timing.learner import Pass


@dataclass(frozen=True)
class SignalSpec:
    cycle_s: float
    red_s: float
    offset_s: float = 0.0  # a red starts at offset + k * cycle; green starts red_s later


def _green_after(spec: SignalSpec, t: float) -> float:
    """The first green start at or after t, or t itself if the light is green at t."""
    phase = (t - spec.offset_s) % spec.cycle_s
    return t if phase >= spec.red_s else t + (spec.red_s - phase)


def simulate_passes(
    spec: SignalSpec,
    n: int,
    *,
    seed: int,
    start_epoch: float = 1_760_000_000.0,
    mean_headway_s: float = 25.0,
    cruise_ms: tuple[float, float] = (8.0, 12.0),
    decel: float = 2.0,
    accel: float = 1.5,
    startup_s: float = 2.0,
    queue_gap_m: float = 7.0,
    gps_noise_m: float = 1.5,
    sample_s: float = 1.0,
    approach_m: float = 250.0,
    exit_m: float = 80.0,
    sampled_fraction: float = 1.0,
) -> list[Pass]:
    """``n`` vehicles arriving at random (exponential headways); each is recorded with probability ``sampled_fraction`` (a phone in
    some cars only). The queue is tracked so later cars wait behind earlier ones."""
    rng = np.random.default_rng(seed)
    passes: list[Pass] = []
    t_arrive = start_epoch
    queue: list[float] = []  # departure times of cars still queued, to find a newcomer's position
    for _ in range(n):
        t_arrive += float(rng.exponential(mean_headway_s))
        v = float(rng.uniform(*cruise_ms))
        # Time the car would reach the stop line at cruise.
        t_line = t_arrive + approach_m / v
        green = _green_after(spec, t_line)
        queue = [d for d in queue if d > t_line]
        if green > t_line or queue:
            pos = len(queue)
            depart = max(green, queue[-1] if queue else green) + startup_s if pos else green + startup_s * 0.5
            stop_s = -queue_gap_m * pos - 2.0
        else:
            depart = None
            stop_s = 0.0
        times: list[float] = []
        pos_s: list[float] = []
        t = t_arrive
        if depart is None:
            while True:
                s = -approach_m + v * (t - t_arrive)
                times.append(t)
                pos_s.append(s)
                if s > exit_m:
                    break
                t += sample_s
        else:
            queue.append(depart)
            brake_d = v * v / (2 * decel)
            t_brake = t_arrive + (approach_m + stop_s - brake_d) / v
            t_stop = t_brake + v / decel
            depart = max(depart, t_stop + 1.0)
            queue[-1] = depart
            accel_t = v / accel
            accel_d = v * v / (2 * accel)
            while True:
                if t < t_brake:
                    s = -approach_m + v * (t - t_arrive)
                elif t < t_stop:
                    dt = t - t_brake
                    s = stop_s - brake_d + v * dt - 0.5 * decel * dt * dt
                elif t < depart:
                    s = stop_s
                elif t < depart + accel_t:
                    dt = t - depart
                    s = stop_s + 0.5 * accel * dt * dt
                else:
                    s = stop_s + accel_d + v * (t - depart - accel_t)
                times.append(t)
                pos_s.append(s)
                if s > exit_m:
                    break
                t += sample_s
        if rng.random() < sampled_fraction:
            noisy = np.asarray(pos_s) + rng.normal(0, gps_noise_m, len(pos_s))
            passes.append((times, list(noisy)))
    return passes


def simulate_random_signal(n: int, *, seed: int, start_epoch: float = 1_760_000_000.0) -> list[Pass]:
    """Passes through a signal with no fixed cycle: each red lasts a random time (like a police-controlled junction)."""
    rng = np.random.default_rng(seed)
    out: list[Pass] = []
    t0 = start_epoch
    for _ in range(n):
        t0 += float(rng.exponential(60.0))
        wait = float(rng.uniform(5, 90))
        v = 10.0
        times, pos = [], []
        t = t0
        s = -250.0
        while s < 80:
            times.append(t)
            pos.append(s + float(rng.normal(0, 1.5)))
            if s < -2.0 or t - t0 > 250 / v + wait:
                s += v
            t += 1.0
        out.append((times, pos))
    return out
