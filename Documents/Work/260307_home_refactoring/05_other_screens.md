# Phase 5: 주행/설정/재생 화면 토큰 적용

## 목표

드로어 외 나머지 화면(주행, 설정, 개발자도구, 재생 컨트롤, 지도 버튼)에
Phase 1에서 정의한 시맨틱 토큰을 적용한다.

## 작업 파일

### 수정

- `Feature/Navigation/NavigationViewController.swift`
- `Feature/Navigation/PlaybackControlView.swift`
- `Feature/Settings/SettingsViewController.swift`
- `Feature/DevTools/DevToolsViewController.swift`
- `Feature/Home/HomeViewController.swift` (지도 컨트롤 버튼)
- `Feature/Home/MapControlButtonsView.swift`

---

## 5-1. NavigationViewController (주행 화면)

### 매뉴버 배너 토큰 적용

```swift
// 변경 전 (하드코딩)
bannerContainer.backgroundColor = UIColor.black.withAlphaComponent(0.85)
bannerContainer.layer.cornerRadius = 12
turnIconView.widthAnchor.constraint(equalToConstant: 48)
distanceLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 48, weight: .bold)
instructionLabel.font = UIFont.systemFont(ofSize: 24, weight: .semibold)

// 변경 후 (토큰)
bannerContainer.backgroundColor = Theme.Banner.backgroundColor
bannerContainer.layer.cornerRadius = Theme.Banner.cornerRadius
turnIconView.widthAnchor.constraint(equalToConstant: Theme.Banner.iconSize)
distanceLabel.font = Theme.Banner.distanceFont
instructionLabel.font = Theme.Banner.instructionFont
```

### 하단바 토큰 적용

```swift
// 변경 전
etaLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)
etaLabel.textColor = Theme.Colors.primary
distanceLabel.font = Theme.Fonts.body
bottomBar.layer.cornerRadius = 16
endButton.heightAnchor.constraint(equalToConstant: 44)

// 변경 후
etaLabel.font = Theme.BottomBar.etaFont
etaLabel.textColor = Theme.BottomBar.etaColor
distanceLabel.font = Theme.BottomBar.infoFont
bottomBar.layer.cornerRadius = Theme.BottomBar.cornerRadius
endButton.heightAnchor.constraint(equalToConstant: Theme.BottomBar.buttonHeight)
```

### 재센터 버튼 토큰 적용

```swift
// 변경 전
recenterButton.widthAnchor.constraint(equalToConstant: 48)
recenterButton.layer.cornerRadius = 24
iconConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)

// 변경 후
recenterButton.widthAnchor.constraint(equalToConstant: Theme.Card.size)
recenterButton.layer.cornerRadius = Theme.Card.cornerRadius
iconConfig = UIImage.SymbolConfiguration(pointSize: Theme.Card.iconSize, weight: .medium)
```

### 안내 종료 버튼

```swift
// 변경 전
endButton.titleLabel?.font = Theme.Fonts.headline
endButton.backgroundColor = Theme.Colors.destructive

// 변경 후
// DrawerActionButton(.destructive, "안내 종료") 사용 또는:
endButton.titleLabel?.font = Theme.Button.Destructive.font
endButton.backgroundColor = Theme.Button.Destructive.backgroundColor
endButton.layer.cornerRadius = Theme.Button.Destructive.cornerRadius
endButton.heightAnchor.constraint(equalToConstant: Theme.Button.Destructive.height)
```

### OverlayContainer 적용 (선택)

```swift
// 매뉴버 배너를 OverlayContainer로 감싸기
let bannerContainer = OverlayContainer(cornerRadius: Theme.Banner.cornerRadius)
// 내부에 turnIcon, distanceLabel, instructionLabel 배치
```

---

## 5-2. PlaybackControlView (재생 컨트롤)

### 토큰 적용

```swift
// 변경 전
container.backgroundColor = UIColor.black.withAlphaComponent(0.85)
container.layer.cornerRadius = 16
statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
statusLabel.textColor = UIColor.white.withAlphaComponent(0.8)
progressView.trackTintColor = UIColor.white.withAlphaComponent(0.3)
progressView.progressTintColor = .systemGreen
playPauseConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
speedLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)

// 변경 후
container.backgroundColor = Theme.Playback.backgroundColor
container.layer.cornerRadius = Theme.Playback.cornerRadius
statusLabel.font = Theme.Playback.statusFont
statusLabel.textColor = Theme.Playback.statusColor
progressView.trackTintColor = UIColor.white.withAlphaComponent(Theme.Playback.trackTintOpacity)
progressView.progressTintColor = Theme.Playback.progressColor
playPauseConfig = UIImage.SymbolConfiguration(pointSize: Theme.Playback.iconSize, weight: .semibold)
speedLabel.font = Theme.Playback.speedFont
```

### OverlayContainer 적용 (선택)

```swift
// PlaybackControlView의 배경을 OverlayContainer로 교체
let container = OverlayContainer(cornerRadius: Theme.Playback.cornerRadius)
```

---

## 5-3. SettingsViewController (설정 화면)

### 토큰 적용

```swift
// 변경 전 (대부분 UIListContentConfiguration 기본값 사용)
// 일부 하드코딩:
config.textProperties.font = ...
config.secondaryTextProperties.font = ...
toggleSwitch.onTintColor = Theme.Colors.primary

// 변경 후
config.textProperties.font = Theme.Table.cellFont
config.textProperties.color = Theme.Table.cellColor
config.secondaryTextProperties.font = Theme.Table.detailFont
config.secondaryTextProperties.color = Theme.Table.detailColor
config.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
    pointSize: Theme.Table.iconPointSize
)
```

### 파괴적 액션 색상

```swift
// 변경 전
config.textProperties.color = .systemRed
config.imageProperties.tintColor = .systemRed

// 변경 후
config.textProperties.color = Theme.Table.destructiveColor
config.imageProperties.tintColor = Theme.Table.destructiveColor
```

---

## 5-4. DevToolsViewController (개발자도구)

### 토큰 적용

설정 화면과 동일한 패턴 적용:

```swift
config.textProperties.font = Theme.Table.cellFont
config.secondaryTextProperties.font = Theme.Table.detailFont
config.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
    pointSize: Theme.Table.iconPointSize
)
```

---

## 5-5. 지도 컨트롤 버튼 (HomeVC / MapControlButtonsView)

### 토큰 적용

```swift
// 변경 전
button.widthAnchor.constraint(equalToConstant: 48)
button.heightAnchor.constraint(equalToConstant: 48)
button.layer.cornerRadius = 24
button.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
let iconConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)

// 변경 후
button.widthAnchor.constraint(equalToConstant: Theme.Card.size)
button.heightAnchor.constraint(equalToConstant: Theme.Card.size)
button.layer.cornerRadius = Theme.Card.cornerRadius
button.backgroundColor = Theme.Card.backgroundColor.withAlphaComponent(Theme.Card.backgroundOpacity)
let iconConfig = UIImage.SymbolConfiguration(pointSize: Theme.Card.iconSize, weight: .medium)
```

---

## 체크리스트

- [ ] NavigationVC: 매뉴버 배너 -> Theme.Banner 토큰 적용
- [ ] NavigationVC: 하단바 -> Theme.BottomBar 토큰 적용
- [ ] NavigationVC: 재센터 버튼 -> Theme.Card 토큰 적용
- [ ] NavigationVC: 안내 종료 버튼 -> Theme.Button.Destructive 토큰 적용
- [ ] PlaybackControlView: Theme.Playback 토큰 적용
- [ ] SettingsVC: Theme.Table 토큰 적용
- [ ] DevToolsVC: Theme.Table 토큰 적용
- [ ] HomeVC 지도 컨트롤 버튼: Theme.Card 토큰 적용
- [ ] OverlayContainer 적용 여부 결정 (배너, 재생 컨트롤)
- [ ] 빌드 및 동작 확인
  - [ ] 주행 화면 배너/하단바 정상 표시
  - [ ] 재생 컨트롤 정상 표시
  - [ ] 설정/개발자도구 테이블 정상 표시
  - [ ] 지도 컨트롤 버튼 정상 표시
  - [ ] 다크모드 전환 시 색상 정상
