#!/usr/bin/env python3
# 서울시 주요 121장소 영역 Shapefile(.shp/.dbf, WGS84) → hotspot_areas.json
# (순수 파이썬, 외부 의존 없음). 폴리곤 링 + 중심점 + 이름/코드/카테고리.
import struct, json, os

BASE = "Documents/Work/260622_live_congestion/서울시 주요 121장소 영역/서울시 주요 121장소 영역"
OUT = "Navigation/Navigation/Resources/hotspot_areas.json"

# --- DBF 속성 ---
def read_dbf(path):
    with open(path, "rb") as f:
        data = f.read()
    num = struct.unpack("<I", data[4:8])[0]
    hlen = struct.unpack("<H", data[8:10])[0]
    rlen = struct.unpack("<H", data[10:12])[0]
    fields, off = [], 32
    while data[off] != 0x0D:
        fd = data[off:off+32]
        name = fd[:11].split(b"\x00")[0].decode("cp949", "ignore")
        flen = fd[16]
        fields.append((name, flen))
        off += 32
    recs = []
    for i in range(num):
        rs = hlen + i * rlen + 1  # +1 deletion flag
        rec, p = {}, rs
        for name, flen in fields:
            val = data[p:p+flen].decode("utf-8", "ignore").strip()
            rec[name] = val
            p += flen
        recs.append(rec)
    return recs

# --- SHP 지오메트리 (polygon type=5) ---
def read_shp(path):
    with open(path, "rb") as f:
        data = f.read()
    off, out = 100, []
    n = len(data)
    while off < n:
        # record header (big-endian)
        content_len = struct.unpack(">I", data[off+4:off+8])[0]  # 16-bit words
        start = off + 8
        shape_type = struct.unpack("<I", data[start:start+4])[0]
        rings = []
        if shape_type == 5:  # Polygon
            p = start + 4 + 32  # skip type + bbox(4 doubles)
            num_parts = struct.unpack("<I", data[p:p+4])[0]; p += 4
            num_points = struct.unpack("<I", data[p:p+4])[0]; p += 4
            parts = list(struct.unpack("<%dI" % num_parts, data[p:p+4*num_parts])); p += 4*num_parts
            pts = struct.unpack("<%dd" % (2*num_points), data[p:p+16*num_points])
            coords = [(pts[2*i], pts[2*i+1]) for i in range(num_points)]  # (lon, lat)
            bounds = parts + [num_points]
            for k in range(num_parts):
                ring = coords[bounds[k]:bounds[k+1]]
                rings.append(ring)
        out.append(rings)
        off = start + content_len * 2
    return out

def simplify(ring, tol=0.00012):
    # 좌표 간 거리가 tol 미만이면 스킵 (포인트 감량, ~12m)
    if len(ring) <= 4: return ring
    out = [ring[0]]
    for x, y in ring[1:-1]:
        px, py = out[-1]
        if abs(x-px) > tol or abs(y-py) > tol:
            out.append((x, y))
    out.append(ring[-1])
    return out

dbf = read_dbf(BASE + ".dbf")
shp = read_shp(BASE + ".shp")
print("dbf records:", len(dbf), "shp records:", len(shp))

areas = []
for rec, rings in zip(dbf, shp):
    if not rings:
        continue
    simp = [simplify(r) for r in rings]
    # 중심점 = 가장 큰 링의 평균
    big = max(simp, key=len)
    clat = sum(p[1] for p in big) / len(big)
    clon = sum(p[0] for p in big) / len(big)
    areas.append({
        "areaName": rec.get("AREA_NM", ""),
        "areaCode": rec.get("AREA_CD", ""),
        "category": rec.get("CATEGORY", ""),
        "center": [round(clat, 5), round(clon, 5)],
        # rings: [[ [lat,lon], ... ], ...]
        "rings": [[[round(lat, 5), round(lon, 5)] for (lon, lat) in r] for r in simp],
    })

areas.sort(key=lambda a: a["areaCode"])
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(areas, f, ensure_ascii=False, separators=(",", ":"))

pts = sum(len(r) for a in areas for r in a["rings"])
print(f"areas={len(areas)}  총 폴리곤점={pts}  파일={os.path.getsize(OUT)//1024}KB")
print("예시:", areas[0]["areaName"], areas[0]["areaCode"], areas[0]["category"], "rings=", len(areas[0]["rings"]))
