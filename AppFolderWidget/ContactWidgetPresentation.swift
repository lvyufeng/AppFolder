import AppFolderKit
import Foundation

extension ContactTarget.Operation {
    var widgetLocalizedName: String {
        switch self {
        case .phone: String(localized: "电话")
        case .message: String(localized: "短信")
        case .faceTimeAudio: String(localized: "FaceTime 语音")
        case .faceTimeVideo: String(localized: "FaceTime 视频")
        }
    }
}
