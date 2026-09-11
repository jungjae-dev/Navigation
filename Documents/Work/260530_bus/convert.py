"""
버스/지하철 정적 데이터 변환 스크립트

사용법:
    python3 convert.py

입력 파일 (같은 폴더에 있어야 함):
    서울시버스정류소위치정보(YYYYMMDD).xlsx   — data.seoul.go.kr OA-15067
    서울교통공사_1_8호선 역사 좌표(위경도) 정보_YYYYMMDD.csv  — data.go.kr/15099316

출력 파일:
    output/bus_stops_seoul.json
    output/subway_stations_seoul.json
    output/subway_lines_seoul.json
    output/version.json

의존성:
    pip install openpyxl
"""

import csv
import json
import os
import glob
from datetime import date

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# 호선 색상
LINE_COLORS = {
    "1": "#0052A4",
    "2": "#00A84D",
    "3": "#EF7C1C",
    "4": "#00A5DE",
    "5": "#996CAC",
    "6": "#CD7C2F",
    "7": "#747F00",
    "8": "#E6186C",
}


def find_file(pattern):
    matches = glob.glob(os.path.join(os.path.dirname(__file__), pattern))
    if not matches:
        raise FileNotFoundError(f"파일을 찾을 수 없음: {pattern}")
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


def convert_subway_stations():
    path = find_file("서울교통공사_1_8호선 역사 좌표*.csv")
    filename = os.path.basename(path)
    import re
    match = re.search(r"_(\d{8})\.", filename)
    version = match.group(1) if match else date.today().strftime("%Y%m%d")

    stations = []
    with open(path, "r", encoding="cp949") as f:
        reader = csv.DictReader(f)
        for row in reader:
            line_num = row["호선"].strip()
            code = row["고유역번호(외부역코드)"].strip().zfill(4)
            name = row["역명"].strip()
            lat = float(row["위도"])
            lng = float(row["경도"])

            existing = next((s for s in stations if s["stationCode"] == code), None)
            if existing:
                line_label = f"{line_num}호선"
                if line_label not in existing["lines"]:
                    existing["lines"].append(line_label)
            else:
                stations.append({
                    "stationCode": code,
                    "name": name,
                    "lat": lat,
                    "lng": lng,
                    "lines": [f"{line_num}호선"],
                })

    result = {
        "version": version,
        "updatedAt": f"{version[:4]}-{version[4:6]}-{version[6:]}",
        "count": len(stations),
        "data": stations,
    }

    out_path = os.path.join(OUTPUT_DIR, "subway_stations_seoul.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, separators=(",", ":"))

    print(f"✅ subway_stations_seoul.json — {len(stations)}개 역 (version: {version})")
    return version


def convert_subway_lines():
    path = find_file("서울교통공사_1_8호선 역사 좌표*.csv")
    version = date.today().strftime("%Y%m%d")

    lines_data = {}
    with open(path, "r", encoding="cp949") as f:
        reader = csv.DictReader(f)
        for row in reader:
            line_num = row["호선"].strip()
            code = row["고유역번호(외부역코드)"].strip().zfill(4)
            if line_num not in lines_data:
                lines_data[line_num] = []
            lines_data[line_num].append(code)

    lines = {}
    for line_num, codes in sorted(lines_data.items(), key=lambda x: int(x[0])):
        key = f"{line_num}호선"
        entry = {
            "color": LINE_COLORS[line_num],
            "stationCodes": codes,
        }
        if line_num == "2":
            entry["circular"] = True
        lines[key] = entry

    result = {
        "version": version,
        "updatedAt": f"{version[:4]}-{version[4:6]}-{version[6:]}",
        "data": lines,
    }

    out_path = os.path.join(OUTPUT_DIR, "subway_lines_seoul.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, separators=(",", ":"))

    print(f"✅ subway_lines_seoul.json — {len(lines)}개 호선 (version: {version})")
    return version


def write_version(bus_ver, station_ver, lines_ver):
    result = {
        "busStops": bus_ver,
        "subwayStations": station_ver,
        "subwayLines": lines_ver,
    }
    out_path = os.path.join(OUTPUT_DIR, "version.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"✅ version.json — {result}")


if __name__ == "__main__":
    print("=== 버스/지하철 정적 데이터 변환 ===\n")
    bus_ver = convert_bus_stops()
    station_ver = convert_subway_stations()
    lines_ver = convert_subway_lines()
    write_version(bus_ver, station_ver, lines_ver)
    print(f"\n출력 위치: {OUTPUT_DIR}")
