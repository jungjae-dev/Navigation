# 완료 기록 — 문서 체계 리팩토링

---
상태: 완료(PR 대기)
기간: 2026-09-11 ~ 2026-09-11
브랜치/PR: chore/docs-restructure / (PR 번호는 머지 시 기입)
스펙: 해당 없음 (plan.md 참조 — Opus·Sonnet 교차 검증 통합안)
후속: 다음 completion.md부터 이 고정 헤더 관례 적용, Gist의 폐기 subway_*.json 정리(선택)
---

## 수행 내용

계획(plan.md) C1~C7 전량 실행:

1. **정리**: 빈 폴더 `Work/2` 삭제, `260501_location_serivce` 오타 리네임, `.DS_Store` 제거 (커밋 전 무료 시점)
2. **gitignore**: specs/ 해제, `Documents/**` ndjson·3자 원본 확장자 블랙리스트(pdf/xlsx/xls/zip/shp/shx/dbf/prj/cpg), `Scripts/TransitData/source/` 제외
3. **specs/ 편입**: 003·004·005 전량(25파일, 텍스트) — CLAUDE.md 죽은 링크 해소 + 현행 설계 백업
4. **Work 커밋 재개**: 260501~260911 19폴더를 시기별 3커밋으로 (문서·ref 이미지만, 원시 데이터 자동 필터)
5. **구조 확정**: Legacy→`Archive/Legacy/`+파일별 인용 금지 배너(Architecture.md의 SwiftUI 오기술 차단), Feature/ 5건→작성일 기준 Work/ 흡수 — 최상위 `Work/`+`Archive/` 2폴더
6. **이정표 재설계**: CLAUDE.md(오리엔테이션·문서 지도·자주 틀리는 것, speckit 블록 보존), constitution v1.1.0(제약 4줄+§Documentation Workflow), 코드 주석 3건 이식(MapMatcher·NavigationSessionManager·OffRouteDetector), AI 자동 메모리 11→4파일
7. **파이프라인 편입**: Scripts/TransitData(버스 정본) 커밋, 260530_bus 중복 데이터 제거(byte-diff 확인 후), speckit 스킬 15종 커밋

## 검증

- 성공 기준 통과: CLAUDE.md가 가리키는 전 경로가 커밋 트리에 실재
- 추적된 ndjson은 승격 픽스처 7건뿐, Documents 하위 0건
- 계획 대비 조정 1건: 지하철 데이터는 "이동 후 제거"가 아니라 **source/에 로컬 보존** — Scripts/TransitData README에서 지하철 기능이 앱에서 제거된 사실을 확인(재도입 시 KRIC 데이터 사용 예정), 따라서 커밋 대상이 아님. 삭제한 파일은 전부 byte-identical 중복 또는 보존된 convert.py+CSV로 재생성 가능
