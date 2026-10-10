# 계획 — 주행 음성 안내 임시 차단

speckit 미사용(소규모 chore). 기존 개발자 토글 패턴(`DevToolsSettings` CurrentValueSubject + UserDefaults, `NavigationViewController` Combine 구독)을 그대로 따른다.

| # | 파일 | 변경 |
|---|---|---|
| 1 | Service/DevTools/DevToolsSettings.swift | `voiceGuidanceEnabled` 플래그·키·setter 추가, 기본 off |
| 2 | Feature/DevTools/DevToolsViewController.swift | DebugRow에 `voiceGuidance` 행 — "음성 안내 (실험)" 토글 |
| 3 | Feature/Navigation/NavigationViewController.swift | `enqueue` 호출을 플래그로 게이트 |
| 4 | Voice/VoiceTTSPlayer.swift | 오디오 세션을 재생 직전에 켜고 큐가 비거나 `stop()`이면 끈다 |
| 5 | Feature/Settings/SettingsViewController.swift | Section에서 `voice` 제거(renumber), VoiceRow·핸들러·속도 피커·voice 구독 삭제. SettingsViewModel의 voice 상태는 기존 UserDefaults 키의 소유자로 유지 |

복원 절차: 이 PR 이전 커밋(`git show 36fcafe:Navigation/Navigation/Feature/Settings/SettingsViewController.swift`)의 voice 섹션을 되살리고 `enqueue` 게이트를 SettingsViewModel.voiceEnabled로 교체.
