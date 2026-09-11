import UIKit

/// 개인정보처리방침 표시 화면. 원본: Documents/Work/260911_launch_v1_prep/privacy_policy.md
final class PrivacyPolicyViewController: UIViewController {

    private let textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return textView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "개인정보처리방침"
        view.backgroundColor = Theme.Colors.background
        textView.backgroundColor = Theme.Colors.background
        textView.text = Self.policyText

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private static let policyText = """
    RoutIn 개인정보처리방침 (초안)

    RoutIn(이하 "본 앱")은 이용자의 개인정보를 중요하게 생각하며, 관련 법령을 준수합니다. \
    본 방침은 본 앱이 어떤 정보를 수집·이용하는지 설명합니다.

    1. 수집하는 정보

    - 위치정보(GPS): 위치 권한 승인 시 실시간 수집. 지도 표시·경로 안내·내 차 찾기에 사용. 기기 내부에서만 처리하며 서버로 전송하지 않습니다.
    - 카메라: 카메라 권한 승인 시 촬영. 지하주차장 기둥 코드 인식(OCR), 차량 위치 확인용 사진에 사용. 영상은 저장하지 않으며 인식용 사진만 기기 내부에 보관합니다.
    - 기기 사용 정보·기기 식별자: Firebase Analytics를 통해 자동 수집되어 서비스 이용 현황 파악·개선에 사용됩니다.
    - 충돌 진단 정보: Firebase Crashlytics를 통해 자동 수집되어 오류 원인 파악·안정성 개선에 사용됩니다.
    - 검색어·좌표: 장소 검색·경로 조회 시 카카오, 서울 열린데이터광장, 버스정보 API 등 각 제공사로 전송됩니다.

    회원가입 절차가 없어 이름·전화번호·이메일 등 회원 식별 정보는 수집하지 않습니다.
    광고 SDK를 사용하지 않으며 광고 식별자(IDFA)는 수집하지 않습니다.

    2. 이용 목적
    지도·길안내·검색·주변 정보 등 핵심 기능 제공, 지하주차장 내 차 찾기, 서비스 안정성 확보 및 이용 현황 기반 개선.

    3. 보유 및 이용 기간
    즐겨찾기·검색기록·주차 위치 사진은 사용자가 직접 삭제하거나 앱을 삭제할 때까지 기기에만 보관되며, \
    개발사가 별도로 수집·보관하지 않습니다. Firebase로 수집되는 정보는 Google의 관련 정책에 따라 보관됩니다.

    4. 제3자 제공 및 위탁
    원칙적으로 개인정보를 제3자에게 제공하지 않습니다. 서비스 제공을 위해 카카오(장소 검색·길찾기), \
    서울특별시 열린데이터광장·버스정보시스템(실시간 대중교통·도시 데이터), Google Firebase(이용 통계·충돌 진단)를 이용합니다.

    5. 이용자의 권리
    위치·카메라 권한은 기기의 설정에서 언제든 철회할 수 있습니다. 즐겨찾기·검색기록은 앱 내 설정에서 직접 삭제할 수 있습니다. \
    권한을 거부해도 일부 기능만 제한되며 앱은 계속 사용할 수 있습니다.

    6. 아동의 개인정보
    본 앱은 만 14세 미만 아동을 주 이용대상으로 하지 않으며, 회원가입 절차가 없어 아동으로부터 별도의 개인정보를 수집하지 않습니다.

    7. 문의처
    개인정보 관련 문의: [담당자 이메일 주소 기입 예정]

    8. 고지의 의무
    본 방침이 변경되는 경우 앱 내 공지 등을 통해 고지합니다.

    시행일자: [출시일 확정 후 기입]
    """
}
