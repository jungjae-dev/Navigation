import Foundation
import MapKit

struct SearchCategory: Hashable {
    let id: String
    let name: String
    let iconName: String
    let query: String
    let kakaoCategoryCode: String?
    let applePOICategory: MKPointOfInterestCategory?

    // MARK: - Hashable (MKPointOfInterestCategory uses rawValue)

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SearchCategory, rhs: SearchCategory) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Kakao Categories

    static let kakaoAll: [SearchCategory] = [
        SearchCategory(id: "kakao_restaurant", name: "음식점", iconName: "fork.knife", query: "음식점", kakaoCategoryCode: "FD6", applePOICategory: nil),
        SearchCategory(id: "kakao_cafe", name: "카페", iconName: "cup.and.saucer.fill", query: "카페", kakaoCategoryCode: "CE7", applePOICategory: nil),
        SearchCategory(id: "kakao_convenience", name: "편의점", iconName: "basket.fill", query: "편의점", kakaoCategoryCode: "CS2", applePOICategory: nil),
        SearchCategory(id: "kakao_mart", name: "대형마트", iconName: "cart.fill", query: "대형마트", kakaoCategoryCode: "MT1", applePOICategory: nil),
        SearchCategory(id: "kakao_gasStation", name: "주유소", iconName: "fuelpump.fill", query: "주유소", kakaoCategoryCode: "OL7", applePOICategory: nil),
        SearchCategory(id: "kakao_parking", name: "주차장", iconName: "p.square.fill", query: "주차장", kakaoCategoryCode: "PK6", applePOICategory: nil),
        SearchCategory(id: "kakao_pharmacy", name: "약국", iconName: "cross.case.fill", query: "약국", kakaoCategoryCode: "PM9", applePOICategory: nil),
        SearchCategory(id: "kakao_hospital", name: "병원", iconName: "cross.fill", query: "병원", kakaoCategoryCode: "HP8", applePOICategory: nil),
        SearchCategory(id: "kakao_bank", name: "은행", iconName: "banknote.fill", query: "은행", kakaoCategoryCode: "BK9", applePOICategory: nil),
        SearchCategory(id: "kakao_subway", name: "지하철역", iconName: "tram.fill", query: "지하철역", kakaoCategoryCode: "SW8", applePOICategory: nil),
        SearchCategory(id: "kakao_attraction", name: "가볼만한곳", iconName: "binoculars.fill", query: "관광명소", kakaoCategoryCode: "AT4", applePOICategory: nil),
        SearchCategory(id: "kakao_accommodation", name: "숙박", iconName: "bed.double.fill", query: "숙박", kakaoCategoryCode: "AD5", applePOICategory: nil),
        SearchCategory(id: "kakao_culture", name: "문화시설", iconName: "theatermasks.fill", query: "문화시설", kakaoCategoryCode: "CT1", applePOICategory: nil),
        SearchCategory(id: "kakao_school", name: "학교", iconName: "graduationcap.fill", query: "학교", kakaoCategoryCode: "SC4", applePOICategory: nil),
        SearchCategory(id: "kakao_academy", name: "학원", iconName: "book.fill", query: "학원", kakaoCategoryCode: "AC5", applePOICategory: nil),
        SearchCategory(id: "kakao_kindergarten", name: "어린이집", iconName: "figure.and.child.holdinghands", query: "어린이집", kakaoCategoryCode: "PS3", applePOICategory: nil),
        SearchCategory(id: "kakao_publicOffice", name: "공공기관", iconName: "building.columns.fill", query: "공공기관", kakaoCategoryCode: "PO3", applePOICategory: nil),
        SearchCategory(id: "kakao_realEstate", name: "중개업소", iconName: "key.fill", query: "중개업소", kakaoCategoryCode: "AG2", applePOICategory: nil),
    ]

    // MARK: - Apple Categories

    static let appleAll: [SearchCategory] = [
        SearchCategory(id: "apple_restaurant", name: "음식점", iconName: "fork.knife", query: "음식점", kakaoCategoryCode: nil, applePOICategory: .restaurant),
        SearchCategory(id: "apple_cafe", name: "카페", iconName: "cup.and.saucer.fill", query: "카페", kakaoCategoryCode: nil, applePOICategory: .cafe),
        SearchCategory(id: "apple_store", name: "매장", iconName: "bag.fill", query: "매장", kakaoCategoryCode: nil, applePOICategory: .store),
        SearchCategory(id: "apple_gasStation", name: "주유소", iconName: "fuelpump.fill", query: "주유소", kakaoCategoryCode: nil, applePOICategory: .gasStation),
        SearchCategory(id: "apple_evCharger", name: "충전소", iconName: "bolt.car.fill", query: "전기차 충전소", kakaoCategoryCode: nil, applePOICategory: .evCharger),
        SearchCategory(id: "apple_parking", name: "주차장", iconName: "p.square.fill", query: "주차장", kakaoCategoryCode: nil, applePOICategory: .parking),
        SearchCategory(id: "apple_pharmacy", name: "약국", iconName: "cross.case.fill", query: "약국", kakaoCategoryCode: nil, applePOICategory: .pharmacy),
        SearchCategory(id: "apple_hospital", name: "병원", iconName: "cross.fill", query: "병원", kakaoCategoryCode: nil, applePOICategory: .hospital),
        SearchCategory(id: "apple_bank", name: "은행", iconName: "banknote.fill", query: "은행", kakaoCategoryCode: nil, applePOICategory: .bank),
        SearchCategory(id: "apple_hotel", name: "호텔", iconName: "bed.double.fill", query: "호텔", kakaoCategoryCode: nil, applePOICategory: .hotel),
        SearchCategory(id: "apple_publicTransport", name: "대중교통", iconName: "bus.fill", query: "대중교통", kakaoCategoryCode: nil, applePOICategory: .publicTransport),
        SearchCategory(id: "apple_park", name: "공원", iconName: "leaf.fill", query: "공원", kakaoCategoryCode: nil, applePOICategory: .park),
        SearchCategory(id: "apple_museum", name: "박물관", iconName: "building.columns.fill", query: "박물관", kakaoCategoryCode: nil, applePOICategory: .museum),
        SearchCategory(id: "apple_movieTheater", name: "영화관", iconName: "film.fill", query: "영화관", kakaoCategoryCode: nil, applePOICategory: .movieTheater),
        SearchCategory(id: "apple_fitnessCenter", name: "헬스장", iconName: "dumbbell.fill", query: "헬스장", kakaoCategoryCode: nil, applePOICategory: .fitnessCenter),
        SearchCategory(id: "apple_school", name: "학교", iconName: "graduationcap.fill", query: "학교", kakaoCategoryCode: nil, applePOICategory: .school),
        SearchCategory(id: "apple_library", name: "도서관", iconName: "books.vertical.fill", query: "도서관", kakaoCategoryCode: nil, applePOICategory: .library),
        SearchCategory(id: "apple_bakery", name: "베이커리", iconName: "birthday.cake.fill", query: "베이커리", kakaoCategoryCode: nil, applePOICategory: .bakery),
        SearchCategory(id: "apple_nightlife", name: "나이트라이프", iconName: "moon.stars.fill", query: "나이트라이프", kakaoCategoryCode: nil, applePOICategory: .nightlife),
        SearchCategory(id: "apple_atm", name: "ATM", iconName: "creditcard.fill", query: "ATM", kakaoCategoryCode: nil, applePOICategory: .atm),
    ]
}
