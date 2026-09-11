# 문서 체계 리팩토링 계획 (Opus·Sonnet 교차 검증 통합안)

작성: 2026-09-11 | 방식: 두 모델이 독립 설계 → 상호 실측 반박 → 수렴안 채택

## 중심 규칙

> **`Documents/Work/` = 사람의 맥락(왜·무엇을·결과). `specs/` = 기계의 계약(어떻게·검증). `CLAUDE.md` = 이정표.**

문서는 종류가 아니라 **수명**으로만 나눈다: 살아있는 문서(CLAUDE.md·constitution·현재 spec)는 틀리면 그 자리에서 고치고, Work/는 append-only 이력(완료 후 수정·이동 금지 — 상호참조 경로가 계약), Archive/는 동결(인용 금지 배너), 원시 데이터·3자 원본은 git 밖.

## 결정 사항

1. **구조**: 최상위 `Work/` + `Archive/` 2폴더. Legacy→`Archive/Legacy/`+경고 배너(Architecture.md는 SwiftUI 오기술 — 현행 UIKit 80:9와 모순), Feature/ 5건→작성일 기준 Work/로 흡수(참조 0건 확인). INDEX.md 미신설 — 폴더명 + completion.md 고정 5줄 헤더 + grep이 인덱스.
2. **git**: specs/ 커밋 전환(죽은 링크 해소·현행 설계 백업, 228K 텍스트). 현장 ndjson 제외(개인 위치 데이터, 승격 기준="테스트가 읽는가"→Fixtures/). 3자 원본 확장자 블랙리스트(pdf/xlsx/xls/zip/shp/shx/dbf/prj/cpg). ref 이미지는 커밋(의도적 예외). `.claude/skills/` 커밋.
3. **TransitData 정본화**: 지하철 유일본(source json 2·output json 2·CSV)을 Scripts/TransitData로 **먼저 이동** 후 260530_bus 중복 데이터 제거. 파이프라인(convert.py·output·SOURCE.md) 커밋 — 앱 정적 데이터 파이프라인이 untracked였던 것이 더 큰 문제.
4. **Claude 3자 분담**: CLAUDE.md=이정표+자주 틀리는 것(~35행, speckit 블록 밖), constitution v1.1.0=규범(제약 4줄+§Documentation Workflow), 자동 메모리=상태만(11→4파일, 사실 3건은 코드 주석으로 이식). 실행 규칙: **메모리에 사실을 적지 않는다.**
5. **명명**: 폴더 `YYMMDD_주제` 유지. 파일 화이트리스트 requirements/plan/completion/analysis.md + 자유. completion.md 고정 헤더(상태·기간·브랜치/PR·스펙·후속 5줄)가 유일한 신규 의무.

## 마이그레이션 커밋 순서

C1 정리(빈 폴더·오타 리네임·DS_Store — 커밋 전 무료 시점) → C2 gitignore → C3 specs 편입 → C4 Work 19폴더(시기별 3분할) → C5 Archive/Feature 이동+배너 → C6 CLAUDE.md·constitution·코드 주석·메모리 → C7 TransitData·skills. C3까지만으로 핵심 리스크 해소, 어느 지점에서 중단해도 손해 없음.

**성공 기준: 새 클론에서 CLAUDE.md가 가리키는 모든 경로가 실재한다.**

## 교차 검증 이력

- Sonnet 양보 4건: specs/ 커밋(무겁다는 근거 반증), Decisions/ 이동(상호참조 4건 파손 버그), Feature/ 누락, 메모리 축소(지목 파일 부재)
- Opus 정정 2건: ndjson 22→13개, "픽스처 완전 중복" 철회. 채택한 Sonnet 개선 6건(별도 브랜치/PR·커밋 분할·porcelain 검증 등)
- 본선 수정 1건: Opus의 260530_bus 삭제 범위가 지하철 데이터 유일본을 포함 → 이동 후 제거로 수정 (Scripts/TransitData에 지하철 파일 부재 실측 확인)
- 상세: 세션 scratchpad의 proposal_opus.md / proposal_sonnet.md / critique_by_* 4건
