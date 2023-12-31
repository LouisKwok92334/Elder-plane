//
//  ChatGPTAPI.swift
//  chatgpt
//
//  Created by Yip Cheuk Wing on 19/11/2023.
//

import Foundation

public final class ChatGPTAPI {

    private let apiKey: String
    private var historyList = [String]()
    private let urlSession = URLSession.shared
    private var urlRequest: URLRequest {
        let url = URL(string: "https://openai.hk-gpt.net/v1/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        headers.forEach {  urlRequest.setValue($1, forHTTPHeaderField: $0) }
        return urlRequest
    }

    let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "YYYY-MM-dd"
        return df
    }()

    private let jsonDecoder = JSONDecoder()
    private var basePrompt: String { "You are ChatGPT, a large language model trained by OpenAI. Answer conversationally. Do not answer as the user. Current date: \(dateFormatter.string(from: Date()))\n\n"
    }

    private var headers: [String: String] {
        [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(apiKey)"
        ]
    }

    private var historyListText: String {
        historyList.joined()
    }

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    private func generateChatGPTPrompt(from text: String) -> String {
        var prompt = basePrompt + historyListText + "User: \(text)\nChatGPT:"
        if prompt.count > (4000 * 4) {
            _ = historyList.dropFirst()
            prompt = generateChatGPTPrompt(from: text)
        }
        return prompt
    }

    private func jsonBody(text: String, stream: Bool = true) throws -> Data {
    
        let jsonBody: [String: Any] = [
            "model": "gpt-4-1106-preview",
            "temperature": 0.8,
            "messages": [["role": "user", "content": "\(text)"]],
            "stream": stream
        ]
        print("json  body ", String(data: try! JSONSerialization.data(withJSONObject: jsonBody), encoding: .utf8)!)
        return try JSONSerialization.data(withJSONObject: jsonBody)
    }

    public func sendMessageStream(text: String) async throws -> AsyncThrowingStream<String, Error> {
        var urlRequest = self.urlRequest
        
        urlRequest.httpBody = try jsonBody(text: text, stream: false)
        let (result, response) = try await urlSession.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw "Invalid response"
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw "Bad Response: \(httpResponse.statusCode)"
        }

        return AsyncThrowingStream<String, Error> { continuation in
            Task(priority: .userInitiated) {
                do {
                    var streamText = ""
                    for try await line in result.lines {
                        if line.hasPrefix("data: "),
                           let data = line.dropFirst(6).data(using: .utf8),
                           let response = try? self.jsonDecoder.decode(CompletionResponse.self, from: data),
                           let text = response.choices.first?.text {
                            streamText += text
                            continuation.yield(text)
                        }
                    }
                    self.historyList.append(streamText)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func sendMessage(text: String) async throws -> String {
        var urlRequest = self.urlRequest
        urlRequest.httpBody = try jsonBody(text: text, stream: false)

        let (data, response) = try await urlSession.data(for: urlRequest)

       print("\(response)")
       print("\(String(data:data, encoding: .utf8)!)")
       
        guard let httpResponse = response as? HTTPURLResponse else {
            throw "Invalid response"
        }

        guard 200...299 ~= httpResponse.statusCode else {
            print("\(response)")
            throw "Bad Response: \(httpResponse.statusCode)"
        }

        do {
            let completionResponse = try self.jsonDecoder.decode(CompletionResponse2.self, from: data)
           let responseText = completionResponse.choices.first?.message.content ?? ""
            self.historyList.append(responseText)
            return responseText
        } catch {
            throw error
        }
    }
}

extension String: CustomNSError {

    public var errorUserInfo: [String : Any] {
        [
            NSLocalizedDescriptionKey: self
        ]
    }
}

struct CompletionResponse: Decodable {
    let choices: [Choice]
}

struct CompletionResponse2: Decodable {
    let choices: [Choice2]
}

struct Choice2: Decodable {
   let index : Int
   let message : TheMessage
}

struct TheMessage : Decodable {
   let role : String
   let content : String
}


struct Choice: Decodable {
    let text: String
}
