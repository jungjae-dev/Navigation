#!/usr/bin/env python3
# 서울 실시간도시데이터(citydata_ppltn) ~120 장소 카탈로그 생성기.
# 1) 후보 장소명을 citydata로 검증(INFO-000 + 데이터 있으면 유효, 응답 AREA_NM/AREA_CD 채택)
# 2) 유효 장소를 Kakao 키워드검색으로 지오코딩 → 좌표
# 3) hotspots.json 출력
import json, sys, time, urllib.parse, urllib.request, re

def read_secret(name):
    with open("Navigation/Secrets.xcconfig", encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith(name):
                return line.split("=", 1)[1].strip()
    return ""

SEOUL = read_secret("SEOUL_OPEN_API_KEY")
KAKAO = read_secret("KAKAO_REST_API_KEY")

# 공식 ~120 장소 후보 (관광특구·고궁/문화유산·인구밀집·발달상권·공원). 철자 오류는 검증에서 걸러짐.
CANDIDATES = [
 # 관광특구
 "강남 MICE 관광특구","동대문 관광특구","명동 관광특구","이태원 관광특구","잠실 관광특구","종로·청계 관광특구","홍대 관광특구",
 # 고궁·문화유산
 "경복궁","광화문·덕수궁","보신각","서울암사동유적","창덕궁·종묘",
 # 인구밀집지역 (역세권)
 "가산디지털단지역","강남역","건대입구역","고덕역","고속터미널역","교대역","구로디지털단지역","구로역","군자역","남구로역",
 "대림역","동대문역","뚝섬역","미아사거리역","발산역","사당역","삼각지역","서울대입구역","서울식물원·마곡나루역","서울역",
 "선릉역","성신여대입구역","수유역","신논현역·논현역","신도림역","신림역","신촌·이대역","양재역","역삼역","연신내역",
 "오목교역·목동운동장","왕십리역","용산역","이태원역","장지역","장한평역","천호역","총신대입구(이수)역","충정로역","합정역",
 "혜화역","홍대입구역(2호선)","회기역","가락시장","서울대벤처타운역","신정네거리역","쌍문역","현충로역","화곡역",
 # 발달상권
 "가락시장","가로수길","광장(전통)시장","김포공항","노량진","덕수궁길·정동길","북촌한옥마을","서촌","성수카페거리","수유리먹자골목",
 "압구정로데오거리","여의도","연남동","영등포 타임스퀘어","용리단길","익선동","창동 신경제 중심지",
 "청담동 명품거리","해방촌·경리단길","DDP(동대문디자인플라자)","DMC(디지털미디어시티)",
 "신촌 스타광장","잠실새내역","서울암사동유적지","남구로역","청와대","북창동","성수역","장지역",
 "용답동","대청역","목동","사당역","뚝섬역","수서역","unknown_drop",
 # 공원
 "강서한강공원","고척돔","광나루한강공원","광화문광장","국립중앙박물관·용산가족공원","난지한강공원","남산공원","노들섬",
 "뚝섬한강공원","망원한강공원","반포한강공원","북서울꿈의숲","서리풀공원·몽마르뜨공원","서울대공원","서울숲공원","아차산",
 "양화한강공원","어린이대공원","여의도한강공원","월드컵공원","응봉산","이촌한강공원","잠실종합운동장","잠실한강공원",
 "잠원한강공원","청계산","청와대",
]

def http_get(url, headers=None, timeout=15):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8")

def citydata_valid(name):
    enc = urllib.parse.quote(name)
    url = f"http://openapi.seoul.go.kr:8088/{SEOUL}/json/citydata_ppltn/1/1/{enc}"
    try:
        d = json.loads(http_get(url))
    except Exception:
        return None
    rows = d.get("SeoulRtd.citydata_ppltn")
    if rows:
        return {"areaName": rows[0]["AREA_NM"], "areaCode": rows[0].get("AREA_CD", "")}
    return None

def kakao_geocode(name):
    for q in (name, re.sub(r"(관광특구|발달상권|\(.*?\)|·.*)", "", name).strip(),
              name.split("·")[0], name.split(" ")[0]):
        if not q:
            continue
        url = "https://dapi.kakao.com/v2/local/search/keyword.json?size=1&query=" + urllib.parse.quote(q)
        try:
            d = json.loads(http_get(url, headers={"Authorization": f"KakaoAK {KAKAO}"}))
        except Exception:
            continue
        docs = d.get("documents")
        if docs:
            return float(docs[0]["y"]), float(docs[0]["x"])
    return None

seen, out, failed = set(), [], []
for nm in CANDIDATES:
    if nm in seen:
        continue
    seen.add(nm)
    v = citydata_valid(nm)
    if not v:
        failed.append((nm, "citydata"))
        continue
    if v["areaName"] in {o["areaName"] for o in out}:
        continue
    coord = kakao_geocode(v["areaName"])
    if not coord:
        failed.append((v["areaName"], "geocode"))
        continue
    out.append({"areaName": v["areaName"], "areaCode": v["areaCode"],
                "lat": round(coord[0], 5), "lon": round(coord[1], 5)})
    print(f"OK {v['areaName']} ({v['areaCode']}) {coord[0]:.4f},{coord[1]:.4f}", flush=True)
    time.sleep(0.05)

out.sort(key=lambda x: x["areaCode"] or x["areaName"])
with open("Navigation/Navigation/Resources/hotspots.json", "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)

print(f"\n=== 유효 {len(out)}곳 저장, 실패 {len(failed)}곳 ===")
for nm, why in failed:
    print(f"  실패({why}): {nm}")
