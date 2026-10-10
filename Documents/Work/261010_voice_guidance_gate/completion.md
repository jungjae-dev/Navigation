# 완료 기록 — 주행 음성 안내 임시 차단

---
상태: 완료
기간: 2026-10-10 ~ 2026-10-10
브랜치/PR: chore/voice-guidance-devtools-gate / PR #62
스펙: 해당 없음 (plan.md 참조)
후속: 음성 안내 문구·타이밍 완성 후 Section.voice 복원 및 게이트를 사용자 설정으로 교체
---

## 수행 내용

plan.md 1~5 전량 반영(소스 5파일, 문서 3파일).

- 개발자 도구 → 디버그 → "음성 안내 (실험)" 토글 신설, 기본 off, UserDefaults `devtools_voice_guidance_enabled`.
- 일반 설정의 "음성 안내" 섹션(토글·속도) 숨김. 기존 `settings_voice_enabled` 키·ViewModel 상태는 그대로 두어 복원 시 재사용.
- 오디오 세션(.playback, duckOthers)은 재생 직전에 켜고 큐가 비거나 `stop()`이면 `setActive(false, .notifyOthersOnDeactivation)`로 끈다 — 음성을 쓰지 않는 동안 타 앱 음악 덕킹 없음.

## 검증

- `xcodebuild build` iPhone 17 Pro 시뮬레이터 성공. 수정 파일에 경고 없음(기존 경고는 Bike·Kakao 모듈의 Swift 6 격리 경고로 무관).
- `xcodebuild test`: 242 통과 / 3 실패. 실패 3건은 모두 이 변경과 무관 — `TurnTypeTests.apple_keepLeft`·`MapMatcherTests.matchReverseHeading_failsForAutomobile`은 main 기존 결함, `LocationSimulatorTests.playEmitsLocations`는 전체 실행 시 5초 타임아웃 경계(5.8s)에 걸린 부하 플레이크로 단독 실행 2회 모두 통과.
- 시뮬레이터 수동 확인(idb로 조작):
  - 앱 기동 정상. 설정 화면에서 "음성 안내" 섹션 사라짐 — 이동수단·지도·차량 아이콘·햅틱·데이터·정보만 표시.
  - 앱 버전 7탭 → 개발자 도구 → 디버그 섹션 마지막에 "음성 안내 (실험)" 토글, 초기값 off.
  - 토글 on → `devtools_voice_guidance_enabled = 1`, off → `0` (앱 컨테이너 plist 확인). 스위치 상태도 동기.
- 미확인: 실제 주행 중 음성 미재생·토글 on 시 재생·재생 종료 후 타 앱 음악 복원. 기기 주행에서 확인 필요.

## 발견 사항

- 설정 화면 "음성 안내" 토글은 애초에 플레이어에 연결돼 있지 않았다(저장만 됨). "음성 속도"도 마찬가지로 플레이어는 `rate = 0.5` 고정이었다. 이번 작업으로 토글이 개발자 도구로 이동하면서 실제로 동작하는 토글이 됐다.

## 교차 리뷰 반영 (Opus·Sonnet, PR #62 코멘트)

반영:
- 오디오 세션이 한 번 켜지면 꺼지지 않던 문제(Opus 1·Sonnet 1) — 큐 소진·`stop()` 시 비활성화, 성공 후에만 활성 플래그.
- off 전환 구독(Opus 3·Sonnet 2) — 주행 중 설정에 들어갈 경로가 없어 초기 emission으로 `stop()` 한 번 부르는 것 외에 동작이 없었음. 구독 삭제, requirements 3 정정.
- SettingsViewController의 미호출 코드(Opus 4·Sonnet 3) — VoiceRow·핸들러·속도 피커·voice 구독 삭제. SettingsViewModel의 voice 상태는 기존 UserDefaults 키 소유자라 유지(Opus 4 의견 채택).
- 주석의 날짜·복원 절차(Sonnet 4·Opus 5) — 이유만 남기고 삭제. 복원 절차는 plan.md로.
- `.systemTeal`(Opus 6·Sonnet 7) — `Theme.Colors.primary`.
- completion 헤더 PR 번호·상태(Opus 7·Sonnet 5), 변경 수 표기(Sonnet 6), voiceSpeed 미연결(Opus 7).

미반영:
- Sonnet 8(스위치가 publisher 미구독) — 값을 바꾸는 경로가 이 화면뿐이고 기존 토글 4개와 같은 패턴. 리뷰어도 실제 문제 없음으로 봄.
