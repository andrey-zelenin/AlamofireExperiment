import Foundation
import Alamofire

public enum ImaggaRouter: URLRequestConvertible {
  static let baseURLPath = "https://api.imagga.com/v2"
  static let authenticationToken = "" // set your credentials

  case upload
  case tags(String)
  case colors(String)

  var method: HTTPMethod {
    switch self {
    case .upload:
      return .post
    case .tags, .colors:
      return .get
    }
  }

  var path: String {
    switch self {
    case .upload:
      return "/uploads" // for upload image
    case .tags:
      return "/tags" // for getting tags
    case .colors:
      return "/colors"  // for getting colors
    }
  }

  public func asURLRequest() throws -> URLRequest {
    let parameters: [String: Any] = {
      switch self {
      case .tags(let contentID):
        return ["image_upload_id": contentID]
      case .colors(let contentID):
        return ["image_upload_id": contentID, "extract_object_colors": 0]
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
