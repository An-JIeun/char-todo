import Foundation
import CoreGraphics

/// 이미지가 없을 때 쓰는 기본 뉴트로 몸통.
enum CharacterSkin: String, Codable, CaseIterable, Identifiable {
    case floppy, cassette, tv

    var id: String { rawValue }

    var label: String {
        switch self {
        case .floppy: "플로피 디스크"
        case .cassette: "카세트 테이프"
        case .tv: "브라운관 TV"
        }
    }

    /// 몸통 높이 / 너비
    var aspect: Double {
        switch self {
        case .floppy: 1.0
        case .cassette: 0.66
        case .tv: 0.86
        }
    }

    var defaultFaceCenter: CGPoint {
        switch self {
        case .floppy: CGPoint(x: 0.5, y: 0.70)
        case .cassette: CGPoint(x: 0.5, y: 0.40)
        case .tv: CGPoint(x: 0.43, y: 0.50)
        }
    }
}

enum EyeStyle: String, Codable, CaseIterable, Identifiable {
    case dot, oval, pixel, happy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dot: "점 눈"
        case .oval: "타원 눈"
        case .pixel: "픽셀 눈"
        case .happy: "웃는 눈 ^^"
        }
    }
}

enum HandStyle: String, Codable, CaseIterable, Identifiable {
    case glove, round, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glove: "하얀 장갑"
        case .round: "동글 손"
        case .none: "없음 (끝이 둥근 팔)"
        }
    }
}

enum FootStyle: String, Codable, CaseIterable, Identifiable {
    case shoe, round, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .shoe: "운동화"
        case .round: "동글 발"
        case .none: "없음 (끝이 둥근 다리)"
        }
    }
}

/// 얼굴 표현 방식
enum FaceStyle: String, Codable, CaseIterable, Identifiable {
    /// 눈·입을 직접 그린다 (기본 스킨, 얼굴 없는 이미지)
    case draw
    /// 이미지의 얼굴은 그대로 두고 깜빡임·말하는 입만 덧그린다
    case overlay
    var id: String { rawValue }
    var label: String {
        switch self {
        case .draw: "직접 그리기"
        case .overlay: "이미지 얼굴 + 깜빡임·입만"
        }
    }
}

/// 팔다리 표현 방식
enum LimbMode: String, Codable, CaseIterable, Identifiable {
    /// 선으로 그린 팔다리
    case drawn
    /// 이미지에 그려진 팔다리를 잘라내 관절처럼 회전 (원본 그림 그대로)
    case cutout
    var id: String { rawValue }
    var label: String {
        switch self {
        case .drawn: "그려서 붙이기"
        case .cutout: "이미지를 파츠로 나누기"
        }
    }
}

enum MouthStyle: String, Codable, CaseIterable, Identifiable {
    case simple, cat
    var id: String { rawValue }
    var label: String {
        switch self {
        case .simple: "둥근 입"
        case .cat: "고양이 입 ω"
        }
    }
}

enum LimbKind: String, CaseIterable, Identifiable {
    case leftArm, rightArm, leftLeg, rightLeg
    var id: String { rawValue }
    var label: String {
        switch self {
        case .leftArm: "왼팔"
        case .rightArm: "오른팔"
        case .leftLeg: "왼다리"
        case .rightLeg: "오른다리"
        }
    }
    var isArm: Bool { self == .leftArm || self == .rightArm }
    var isLeft: Bool { self == .leftArm || self == .leftLeg }
}

struct LimbConfig: Codable, Equatable {
    var enabled = true
    /// 몸통 사각형 기준 단위 좌표 (0~1, 범위 밖도 허용)
    var anchor: CGPoint
    /// 몸통 너비 대비 길이
    var length: Double
    /// 몸통 너비 대비 두께
    var thickness: Double = 0.05
    /// 기본 각도(도). 0 = 아래, + = 오른쪽, − = 왼쪽
    var restAngle: Double
    /// 흔들림 폭(도)
    var swing: Double
    /// 컷아웃 모드: 이미지에서 이 팔다리에 해당하는 영역 (몸통 단위 좌표). anchor가 회전축.
    var spriteRect: CGRect? = nil
    /// 파츠 모드: 팔·발 위에 찍은 점. 이 점과 이어진 팔다리 모양을 자동으로 잘라낸다.
    var grabPoint: CGPoint? = nil
}

/// 파츠 모드의 머리 영역 (얼굴 표정은 머리와 함께 움직인다)
struct HeadPart: Codable, Equatable {
    var enabled = false
    /// 몸통 단위 좌표 (머리·몸이 한 덩어리인 캐릭터는 끄는 것이 자연스럽다)
    var rect = CGRect(x: 0, y: 0, width: 1, height: 0.62)
    /// 목(회전축)
    var pivot = CGPoint(x: 0.5, y: 0.62)
}

struct FaceConfig: Codable, Equatable {
    var enabled = true
    var center = CGPoint(x: 0.5, y: 0.42)
    var eyeSpacing = 0.26
    var eyeSize = 0.075
    var mouthOffset = 0.11
    var mouthWidth = 0.13
    var eyeStyle: EyeStyle = .dot
    var blush = true
    var colorHex = "#1E1E1E"
    var style: FaceStyle = .draw
    /// 오버레이 모드에서 눈꺼풀·입 가림에 쓰는 피부색
    var skinHex = "#FAEFD3"
    var mouthStyle: MouthStyle = .simple
    /// 입 벌릴 때 송곳니
    var fangs = false
}

/// 플로팅 캐릭터 설정: 이미지 + 팔·다리·얼굴 리깅.
struct CharacterRig: Codable, Equatable {
    var skin: CharacterSkin = .floppy
    /// 앱 지원 폴더에 저장된 사용자 이미지 파일명
    var imageFile: String?
    /// 몸통 너비(pt)
    var size: Double = 96
    var limbColorHex = "#1E1E1E"
    /// 지정하면 팔다리를 '채움색 + 외곽선(limbColor)' 으로 그린다
    var limbFillHex: String? = nil
    var handStyle: HandStyle = .glove
    var footStyle: FootStyle = .shoe
    /// 팔다리를 몸통 앞에 그린다 (이미지에 원래 팔다리가 있을 때 덮어쓰기용)
    var limbsInFront = false
    var bodyColorHex: String? = nil
    var leftArm = LimbConfig(anchor: CGPoint(x: 0.04, y: 0.55), length: 0.34, restAngle: -38, swing: 14)
    var rightArm = LimbConfig(anchor: CGPoint(x: 0.96, y: 0.55), length: 0.34, restAngle: 38, swing: 14)
    var leftLeg = LimbConfig(anchor: CGPoint(x: 0.34, y: 0.98), length: 0.26, thickness: 0.055, restAngle: -3, swing: 7)
    var rightLeg = LimbConfig(anchor: CGPoint(x: 0.66, y: 0.98), length: 0.26, thickness: 0.055, restAngle: 3, swing: 7)
    var face = FaceConfig(center: CharacterSkin.floppy.defaultFaceCenter)
    var limbMode: LimbMode = .drawn
    var head = HeadPart()
    /// 둥실거림 크기 (몸통 너비 대비)
    var bobAmount = 0.035
    var speed = 1.0
    /// 혼자 있을 때 행동하는 빈도 (0 = 가만히, 1 = 아주 활발)
    var liveliness = 0.6
    /// 점프 높이 (몸통 너비 대비)
    var jumpHeight = 0.3
    /// 말랑함: 점프·착지 때 찌그러지고 늘어나는 정도 (0~1)
    var squash = 0.7
    /// 가끔 원래 자리 근처를 걸어 다니기
    var wanders = true

    func limb(_ kind: LimbKind) -> LimbConfig {
        switch kind {
        case .leftArm: leftArm
        case .rightArm: rightArm
        case .leftLeg: leftLeg
        case .rightLeg: rightLeg
        }
    }

    mutating func setLimb(_ kind: LimbKind, _ value: LimbConfig) {
        switch kind {
        case .leftArm: leftArm = value
        case .rightArm: rightArm = value
        case .leftLeg: leftLeg = value
        case .rightLeg: rightLeg = value
        }
    }

    static let `default` = CharacterRig()
}

/// 캐릭터 표정·동작 상태
enum CharacterMood: String, CaseIterable, Identifiable {
    case idle, listening, thinking, talking, happy, sleepy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .idle: "대기"
        case .listening: "듣는 중"
        case .thinking: "생각 중"
        case .talking: "말하는 중"
        case .happy: "신남"
        case .sleepy: "졸림"
        }
    }
}
