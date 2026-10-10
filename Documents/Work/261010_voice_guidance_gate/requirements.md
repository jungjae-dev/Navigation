# 주행 음성 안내 임시 차단 — 요구사항

작성: 2026-10-10 | 상태: 완료 | 관련: Navigation/Navigation/Voice/VoiceTTSPlayer.swift, Service/DevTools/DevToolsSettings.swift

## 배경

주행 중 `RouteGuide.voiceCommand`가 있으면 `VoiceTTSPlayer`가 TTS를 재생한다. 안내 문구·타이밍이 미완성 상태라 사용자에게 노출되면 안 된다.
설정 화면의 "음성 안내" 토글은 UserDefaults에 저장만 되고 플레이어와 연결돼 있지 않아 꺼도 음성이 나왔다(죽은 토글).

## 요구

1. 일반 사용자는 음성 안내 기능의 존재를 모른다 — 설정 화면에서 "음성 안내" 섹션(토글·속도)을 숨긴다.
2. 개발자(나)만 켤 수 있다 — 개발자 도구(앱 버전 7탭 해금) "디버그" 섹션에 토글을 둔다. 기본 off.
3. 토글 off 시 재생 중인 안내도 즉시 끊는다.
4. 음성을 꺼도 `.playback` 오디오 세션이 켜져 타 앱 음악이 덕킹되는 부작용이 없어야 한다.

## 비요구

- 음성 문구·타이밍 개선. 별도 작업.
- `#if DEBUG` 차단 — TestFlight에서 직접 들어봐야 하므로 하지 않는다. 출시 빌드에도 개발자 메뉴가 포함되는 기존 정책(parkingDebugEnabled, DR-005)과 동일.
