import Foundation

struct TranscriptEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let text: String
    let languageCode: String
    let microphoneName: String

    init(
        id: UUID = UUID(),
        createdAt: Date,
        text: String,
        languageCode: String,
        microphoneName: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.languageCode = languageCode
        self.microphoneName = microphoneName
    }
}
