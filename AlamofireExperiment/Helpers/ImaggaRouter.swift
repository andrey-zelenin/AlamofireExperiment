/*
 * Copyright (c) 2017 Andrey Zelenin
 *
 * Original idea took from https://www.raywenderlich.com
 *
 */

import Foundation
import Alamofire

public enum ImaggaRouter: URLRequestConvertible {
  static let baseURLPath = "http://api.imagga.com/v1"
  static let authenticationToken = "Basic xxx" // set your credentials

  case content
  case tags(String)
  case colors(String)

  var method: HTTPMethod {
    switch self {
    case .content:
      return .post
    case .tags, .colors:
      return .get
    }
  }

  var path: String {
    switch self {
    case .content:
      return "/content" // for upload image
    case .tags:
      return "/tagging" // for getting tags
    case .colors:
      return "/colors"  // for getting colors
    }
  }

  public func asURLRequest() throws -> URLRequest {
    let parameters: [String: Any] = {
      switch self {
      case .tags(let contentID):
        return ["content": contentID]
      case .colors(let contentID):
        return ["content": contentID, "extract_object_colors": 0]
      default:
        return [:]
      }
    }()

    let url = try ImaggaRouter.baseURLPath.asURL()

    var request = URLRequest(url: url.appendingPathComponent(path))
    request.httpMethod = method.rawValue
    request.setValue(ImaggaRouter.authenticationToken, forHTTPHeaderField: "Authorization") // basic auth
    request.timeoutInterval = TimeInterval(10 * 1000)

    return try URLEncoding.default.encode(request, with: parameters)
  }
}
