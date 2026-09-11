"""
버스 정류장 정적 데이터 변환 스크립트

사용법:
    python3 convert.py

입력 파일 (source/ 폴더):
    서울시버스정류소위치정보(YYYYMMDD).xlsx   — data.seoul.go.kr OA-15067

출력 파일:
    output/bus_stops_seoul.json
    output/version.json

의존성:
    pip install openpyxl
"""

import json
import os
import glob
from datetime import date

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)


def find_file(pattern):
    source_dir = os.path.join(os.path.dirname(__file__), "source")
    matches = glob.glob(os.path.join(source_dir, pattern))
    if not matches:
        raise FileNotFoundError(f"파일을 찾을 수 없음: source/{pattern}")
    return sorted(matches)[-1]  # 최신 파일 사용


def convert_bus_stops():
    import openpyxl

    path = find_file("서울시버스정류소위치정보*.xlsx")
    filename = os.path.basename(path)
    # 파일명에서 날짜 추출 (예: 서울시버스정류소위치정보(20260506).xlsx → 20260506)
    import re
    match = re.search(r"\((\d{8})\)", filename)
    version = match.group(1) if match else date.today().strftime("%Y%m%d")

    wb = openpyxl.load_workbook(path)
    ws = wb.active

    stops = []
    for i, row in enumerate(ws.iter_rows(values_only=True)):
        if i == 0:
            continue
        node_id, ars_id, name, x, y, stop_type = row
        if node_id is None:
            continue
        stops.append({
            "stId": str(int(node_id)),
            "arsId": str(ars_id).zfill(5),
            "name": str(name),
            "lat": float(y),
            "lng": float(x),
        })

    result = {
        "version": version,
        "updatedAt": f"{version[:4]}-{version[4:6]}-{version[6:]}",
        "count": len(stops),
        "data": stops,
    }

    out_path = os.path.join(OUTPUT_DIR, "bus_stops_seoul.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, separators=(",", ":"))

    print(f"✅ bus_stops_seoul.json — {len(stops)}개 정류장 (version: {version})")
    return version


def write_version(bus_ver):
    result = {
        "busStops": bus_ver,
    }
    out_path = os.path.join(OUTPUT_DIR, "version.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"✅ version.json — {result}")


if __name__ == "__main__":
    print("=== 버스 정류장 정적 데이터 변환 ===\n")
    bus_ver = convert_bus_stops()
    write_version(bus_ver)
    print(f"\n출력 위치: {OUTPUT_DIR}")
