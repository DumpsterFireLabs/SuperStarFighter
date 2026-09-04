#!/usr/bin/env python3
"""Validate coverage and summarize the shield/population study's retained raw rows."""
import argparse
from collections import Counter
import json
from pathlib import Path
from statistics import median


def distribution(values):
    values = sorted(value for value in values if value is not None)
    return dict(samples=len(values), minimum=min(values), median=median(values), maximum=max(values)) if values else dict(samples=0)


def summarize(shield, pacing):
    seeds = shield["seed_count"]
    assert shield["schema"] == pacing["schema"] == 2
    assert pacing["seed_count"] == seeds and seeds >= 3, "Need at least three matching seed cases"
    assert len(shield["shield_matchups"]) == 3 * 3 * seeds * 2
    assert len(shield["shield_volleys"]) == 48
    assert len(pacing["pacing"]) == 5 * 3 * seeds
    assert all(not row["incomplete"] and len(row["heats"]) == 3 for row in pacing["pacing"]), "Pacing study is incomplete"
    matchups = []
    pairs = sorted({(row["left"], row["right"]) for row in shield["shield_matchups"]})
    for left, right in pairs:
        rows = [row for row in shield["shield_matchups"] if (row["left"], row["right"]) == (left, right)]
        assert len({(row["map"], row["seed"], row["swapped"]) for row in rows}) == 3 * seeds * 2
        matchups.append(dict(left=left, right=right, outcomes=dict(Counter(row["winner"] for row in rows)),
                             duration_seconds=distribution(row["seconds"] for row in rows),
                             left_blocks=sum(row["left_defense"]["blocks"] for row in rows),
                             left_breaks=sum(row["left_defense"]["breaks"] for row in rows),
                             left_locked_fraction=sum(row["left_defense"]["locked_seconds"] for row in rows) / sum(row["seconds"] for row in rows)))
    groups = []
    for mode, players in sorted({(row["mode"], row["players"]) for row in pacing["pacing"]}):
        cases = [row for row in pacing["pacing"] if (row["mode"], row["players"]) == (mode, players)]
        assert len({row["seed"] for row in cases}) == seeds
        heats = [heat for row in cases for heat in row["heats"]]
        assert all("time_limit_reached" in heat for heat in heats), "Missing authoritative timeout classification"
        elimination = mode in ("Death Match", "Team Death Match")
        groups.append(dict(mode=mode, players=players, heats=len(heats), maps=sorted({heat["map"] for heat in heats}),
                           timeouts=sum(heat["time_limit_reached"] for heat in heats),
                           duration_seconds=distribution(heat["duration_seconds"] for heat in heats),
                           first_contact_seconds=distribution(heat["first_contact_seconds"] for heat in heats),
                           eliminated_wait_seconds=distribution(value for heat in heats for value in heat["eliminated_seconds"].values()) if elimination else None))
    return dict(protocol=shield["protocol"], seed_count=seeds, shield_matchups=matchups, pacing=groups,
                limitations="Exploratory deterministic bots, not human win rates or physical LAN acceptance. Objective deaths can recur; eliminated wait is reported only for elimination modes.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shield", type=Path, required=True)
    parser.add_argument("--pacing", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = summarize(json.loads(args.shield.read_text(encoding="utf-8")), json.loads(args.pacing.read_text(encoding="utf-8")))
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Gameplay coverage verified: {len(result['pacing'])} population/mode groups; summary={args.output}")


if __name__ == "__main__":
    main()
