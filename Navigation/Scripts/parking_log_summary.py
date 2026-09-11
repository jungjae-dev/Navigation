#!/usr/bin/env python3
"""주차 관측 NDJSON 로그 표준 요약 — 튜닝 루프의 공통 메트릭.

사용:  python3 parking_log_summary.py <로그파일.ndjson 또는 폴더> [...]

세션당 한 블록 — 전/후 비교, 주차장별·기기별 비교의 기준 지표:
  · 위치 확보율(raycast/depth 분리) — sceneDepth 폴백 효과 측정 (src 필드)
  · 첫 안내까지 시간 / 상태 전이 타임라인 — 사용성(수렴 속도)
  · 도착 여부·시점, 도착 순간 목표 추정 오차(기기 위치 ≈ ground truth 근사)
  · 기각 사유 분포 — 파서·필터 튜닝 신호
"""
import json
import math
import sys
import collections
from pathlib import Path


def summarize(path: Path) -> None:
    events = [json.loads(l) for l in path.open() if l.strip()]
    if not events:
        print(f"\n== {path.name}: 빈 파일")
        return
    start = events[0]
    duration = events[-1].get("t", 0)
    mode = start.get("mode", "?")

    print(f"\n{'='*74}\n{path.name}  [{mode}, {duration:.0f}s, lidar={start.get('lidar')}]")
    if target := start.get("target"):
        print(f"  목표 {target.get('raw')} (floor={target.get('floor')}, skeleton={target.get('skeleton')}) "
              f"인접={start.get('neighbors')}")

    # 위치 확보율 + src 분리 (sceneDepth 폴백 효과)
    obs = [e for e in events if e["e"] == "codeObserved"]
    with_pos = [e for e in obs if e.get("pos")]
    src = collections.Counter(e.get("src", "n/a") for e in with_pos)
    if obs:
        print(f"  관측 {len(obs)}건 중 위치 확보 {len(with_pos)}건 ({100*len(with_pos)/len(obs):.0f}%) "
              f"— src: {dict(src)}")
        codes = collections.Counter(e["raw"] for e in obs)
        print(f"  코드(횟수): {dict(codes.most_common(10))}")

    rejected = collections.Counter(e["reason"] for e in events if e["e"] == "candidateRejected")
    if rejected:
        print(f"  기각: {dict(rejected)}")
    fails = [e for e in events if e["e"] == "raycastFailed"]
    if fails:
        print(f"  raycastFailed {len(fails)}건 (최대 연속 {max(e['consecutive'] for e in fails)})")

    # 상태 전이 타임라인 + 첫 안내까지 시간
    transitions = [e for e in events if e["e"] == "stateTransition"]
    for t in transitions:
        print(f"    {t['t']:6.1f}s  {t['from']} → {t['to']}  ({t['trigger']})")
    first_guidance = next((e["t"] for e in events if e["e"] == "guidanceShown"
                           and e.get("arrowDeg") is not None), None)
    if first_guidance is not None:
        print(f"  첫 방향 안내: {first_guidance:.1f}s")

    # 신뢰도 분포 (과신 상한 튜닝 신호)
    grid = [e for e in events if e["e"] == "gridUpdated"]
    if grid:
        conf = collections.Counter(g.get("confidence") for g in grid)
        stages = collections.Counter(g["stage"].split("(")[0] for g in grid)
        print(f"  grid {len(grid)}건 — stage {dict(stages)}, confidence {dict(conf)}")

    # 설계 개정 v2 주 지표: 화살표 가동률 + targetEst 자기불안정성 + 외삽 레버
    if grid:
        guiding = [g for g in grid if g["stage"].startswith(("axisGuidance", "gridGuidance"))]
        print(f"  화살표 가동률: {len(guiding)}/{len(grid)} ({100*len(guiding)/len(grid):.0f}%)")
        ests = [g["targetEst"] for g in grid if g.get("targetEst")]
        if len(ests) >= 2:
            jumps = [math.hypot(a[0]-b[0], a[1]-b[1]) for a, b in zip(ests, ests[1:])]
            print(f"  targetEst 자기불안정성: 최대 한-스텝 {max(jumps):.1f}m, 누적 이동 {sum(jumps):.1f}m")
        levers = [g["lever"] for g in grid if g.get("lever") is not None]
        if levers:
            print(f"  외삽 레버(G1): 중앙 {sorted(levers)[len(levers)//2]:.2f}, 최대 {max(levers):.2f} (상한 2.5)")

    # 도착 + 오차 근사 (보조 지표 — 성공 세션 편향·바닥오차 3~5m 주의, 설계 개정 v2)
    end = next((e for e in events if e["e"] == "sessionEnd"), None)
    poses = [e for e in events if e["e"] == "devicePose"]
    if end:
        print(f"  종료: {end.get('by')} @ {end.get('elapsed', 0):.0f}s")
        if end.get("by") == "target-recognition" and poses:
            last_pose = poses[-1]["pos"]
            last_est = next((g.get("targetEst") for g in reversed(grid) if g.get("targetEst")), None)
            if last_est:
                err = math.hypot(last_pose[0] - last_est[0], last_pose[2] - last_est[1])
                print(f"  🎯 도착 순간 목표 추정 오차 ≈ {err:.1f}m "
                      f"(기기 ({last_pose[0]:.1f},{last_pose[2]:.1f}) vs 추정 ({last_est[0]:.1f},{last_est[1]:.1f}))")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    files: list[Path] = []
    for arg in sys.argv[1:]:
        p = Path(arg)
        files += sorted(p.glob("*.ndjson")) if p.is_dir() else [p]
    for f in files:
        summarize(f)
    print()


if __name__ == "__main__":
    main()
