import Foundation
import AppKit

// MARK: - Response Models

private let apiKey: String = {
    if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
       let data = try? Data(contentsOf: url),
       let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
       let key = dict["ANTHROPIC_API_KEY"], !key.isEmpty {
        return key
    }
    return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
}()

struct CanvasResult: Codable {
    let mode: String
    let intent: String
    let title: String
    let cards: [CardResult]
    let groups: [GroupResult]
    let connections: [ConnectionResult]
    let sections: [SectionResult]
    let question: String
}

struct CardResult: Codable {
    let id: String
    let label: String
    let groupId: String
}

struct GroupResult: Codable {
    let id: String
    let title: String
    let color: String
    let summary: String
}

struct ConnectionResult: Codable {
    let from: String
    let to: String
    let label: String
    let type: String
    let reasoning: String
}

struct SectionResult: Codable {
    let heading: String
    let items: [String]
}

// MARK: - Errors

enum ClaudeServiceError: LocalizedError {
    case imageConversionFailed(index: Int)
    case requestBuildFailed
    case httpError(statusCode: Int, body: String)
    case apiError(message: String)
    case emptyResponse
    case jsonDecodeFailed(raw: String, error: Error)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed(let i):
            return "Failed to convert image \(i) to JPEG data."
        case .requestBuildFailed:
            return "Failed to serialize request body."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .apiError(let message):
            return "Claude API error: \(message)"
        case .emptyResponse:
            return "Claude returned an empty response."
        case .jsonDecodeFailed(let raw, let error):
            return "Failed to decode JSON: \(error.localizedDescription)\nRaw: \(raw.prefix(500))"
        }
    }
}

// MARK: - API Response Structs

private struct APIResponse: Codable {
    let content: [APIContent]?
    let error: APIErrorBody?
}

private struct APIContent: Codable {
    let type: String
    let text: String?
}

private struct APIErrorBody: Codable {
    let type: String?
    let message: String
}

// MARK: - Service

actor ClaudeService {
    static let shared = ClaudeService()

    private let url = URL(string: "https://api.anthropic.com/v1/messages")!

    func analyze(images: [NSImage]) async throws -> CanvasResult {
        // 1. Build content array
        var content: [[String: Any]] = []

        for (index, image) in images.enumerated() {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            else {
                throw ClaudeServiceError.imageConversionFailed(index: index)
            }

            let base64 = jpegData.base64EncodedString()

            // Image block
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ] as [String: String]
            ])

            // Label block
            content.append([
                "type": "text",
                "text": "Image \(index) id:c\(index)"
            ])
        }

        // Final instruction block
        content.append([
            "type": "text",
            "text": "Follow the system prompt. Analyze these images as a collection. Return ONLY the JSON object."
        ])

        // 2. Build request body
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1500,
            "system": SystemPrompt.canvas,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw ClaudeServiceError.requestBuildFailed
        }

        // 3. Build URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData

        // 4. Execute
        let (data, response) = try await URLSession.shared.data(for: request)

        // 5. Check HTTP status
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
            throw ClaudeServiceError.httpError(statusCode: httpResponse.statusCode, body: bodyString)
        }

        // 6. Check for API-level error
        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        if let apiError = apiResponse.error {
            throw ClaudeServiceError.apiError(message: apiError.message)
        }

        // 7. Extract text from first content block
        guard let text = apiResponse.content?.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw ClaudeServiceError.emptyResponse
        }

        // 8. Strip markdown code fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // 9. Decode into CanvasResult
        guard let resultData = cleaned.data(using: .utf8) else {
            throw ClaudeServiceError.emptyResponse
        }

        do {
            return try JSONDecoder().decode(CanvasResult.self, from: resultData)
        } catch {
            throw ClaudeServiceError.jsonDecodeFailed(raw: cleaned, error: error)
        }
    }
}
