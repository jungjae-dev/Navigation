# 완료 기록 — 주행 음성 안내 임시 차단

---
상태: 완료(PR 대기)
기간: 2026-10-10 ~ 2026-10-10
브랜치/PR: chore/voice-guidance-devtools-gate / (PR 번호는 머지 시 기입)
스펙: 해당 없음 (plan.md 참조)
후속: 음성 안내 문구·타이밍 완성 후 Section.voice 복원 및 게이트를 사용자 설정으로 교체
---

## 수행 내용

plan.md 1~5 전량 반영. 변경 5파일, +51/-42.

- 개발자 도구 → 디버그 → "음성 안내 (실험)" 토글 신설, 기본 off, UserDefaults `devtools_voice_guidance_enabled`.
- 일반 설정의 "음성 안내" 섹션(토글·속도) 숨김. 기존 `settings_voice_enabled` 키·ViewModel 상태는 그대로 두어 복원 시 재사용.
- off 전환 시 `VoiceTTSPlayer.stop()`으로 재생 중 안내 즉시 중단.
- 오디오 세션(.playback, duckOthers) 활성화를 첫 재생 직전으로 지연 — 음성 미사용 시 타 앱 음악 덕킹 없음.

## 검증

- `xcodebuild build` iPhone 17 Pro 시뮬레이터 성공. 수정 파일에 경고 없음(기존 경고는 Bike·Kakao 모듈의 Swift 6 격리 경고로 무관).
- `xcodebuild test`: 242 통과 / 3 실패. 실패 3건은 모두 이 변경과 무관 — `TurnTypeTests.apple_keepLeft`·`MapMatcherTests.matchReverseHeading_failsForAutomobile`은 main 기존 결함, `LocationSimulatorTests.playEmitsLocations`는 전체 실행 시 5초 타임아웃 경계(5.8s)에 걸린 부하 플레이크로 단독 실행 2회 모두 통과.
- 시뮬레이터 수동 확인(idb로 조작):
  - 앱 기동 정상. 설정 화면에서 "음성 안내" 섹션 사라짐 — 이동수단·지도·차량 아이콘·햅틱·데이터·정보만 표시.
  - 앱 버전 7탭 → 개발자 도구 → 디버그 섹션 마지막에 "음성 안내 (실험)" 토글, 초기값 off.
  - 토글 on → `devtools_voice_guidance_enabled = 1`, off → `0` (앱 컨테이너 plist 확인). 스위치 상태도 동기.
- 미확인: 실제 주행 중 음성 미재생·토글 on 시 재생·off 전환 시 즉시 중단. 기기 주행에서 확인 필요.

## 발견 사항

- 설정 화면 "음성 안내" 토글은 애초에 플레이어에 연결돼 있지 않았다(저장만 됨). 이번 작업으로 토글이 개발자 도구로 이동하면서 실제로 동작하는 토글이 됐다.
