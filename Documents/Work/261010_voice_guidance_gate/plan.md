# 계획 — 주행 음성 안내 임시 차단

speckit 미사용(소규모 chore). 기존 개발자 토글 패턴(`DevToolsSettings` CurrentValueSubject + UserDefaults, `NavigationViewController` Combine 구독)을 그대로 따른다.

| # | 파일 | 변경 |
|---|---|---|
| 1 | Service/DevTools/DevToolsSettings.swift | `voiceGuidanceEnabled` 플래그·키·setter 추가, 기본 off |
| 2 | Feature/DevTools/DevToolsViewController.swift | DebugRow에 `voiceGuidance` 행 — "음성 안내 (실험)" 토글 |
| 3 | Feature/Navigation/NavigationViewController.swift | `enqueue` 호출을 플래그로 게이트, off 전환 구독 시 `stop()` |
| 4 | Voice/VoiceTTSPlayer.swift | 오디오 세션 활성화를 init → 첫 재생 직전으로 지연 |
| 5 | Feature/Settings/SettingsViewController.swift | Section에서 `voice` 제거(renumber), 세 switch의 voice 분기 삭제. VoiceRow·핸들러·SettingsViewModel의 voice 상태는 복원 대비로 유지 |

복원 절차: Section에 `case voice` 재추가 + 세 switch 분기 복원 + `enqueue` 게이트를 SettingsViewModel.voiceEnabled로 교체.
