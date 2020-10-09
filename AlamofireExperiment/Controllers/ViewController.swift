import UIKit
import Alamofire

class ViewController: UIViewController {

  @IBOutlet weak var takePictureButton: UIButton!
  @IBOutlet weak var imageView: UIImageView!
  @IBOutlet weak var progressView: UIProgressView!
  @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
  @IBOutlet weak var networkStatus: UILabel!

  @IBAction func takePicture(_ sender: UIButton) {
    let picker = UIImagePickerController()
    
    picker.delegate = self
    picker.allowsEditing = false

    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      picker.sourceType = .camera
    } else {
      picker.sourceType = .photoLibrary
      picker.modalPresentationStyle = .fullScreen
    }

    present(picker, animated: true)
  }

  // Properties
  fileprivate var tags: [String]?
  fileprivate var colors: [PhotoColor]?
  fileprivate var reachabilityManager: Reachability?

  deinit {
      stopNotifier()
  }

  // View Life Cycle
  override func viewDidLoad() {
    super.viewDidLoad()
    
    stopNotifier()

    guard !UIImagePickerController.isSourceTypeAvailable(.camera) else { return }

    reachabilityManager = Reachability()
    
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reachabilityChanged(_:)),
      name: .reachabilityChanged,
      object: reachabilityManager
    )

    do {
      try reachabilityManager?.startNotifier()
    } catch {
      print("Could not start reachability notifier")
    }

    takePictureButton.setTitle("Select Photo", for: .normal)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    imageView.image = nil
  }

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if segue.identifier == "ShowResults" {
      guard let controller = segue.destination as? TagsColorsViewController else { return }
    
      controller.tags = tags
      controller.colors = colors
    }
  }

  func startNotifier() {
    do {
      try reachabilityManager?.startNotifier()
    } catch {
      networkStatus.backgroundColor = .red
      networkStatus.text = "Unable to start\nnotifier"

      return
    }
  }

  func stopNotifier() {
    reachabilityManager?.stopNotifier()
    
    NotificationCenter.default.removeObserver(self, name: .reachabilityChanged, object: nil)

    reachabilityManager = nil
  }

  @objc func reachabilityChanged(_ note: Notification) {
    guard let reachability = note.object as? Reachability else { return }

    if reachability.connection != .none {
      networkStatus.text = "Connected"
      networkStatus.backgroundColor = .blue
    } else {
      networkStatus.text = "Not connected"
      networkStatus.backgroundColor = .red
    }
  }
}

// UIImagePickerControllerDelegate
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    // Local variable inserted by Swift 4.2 migrator.
    let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)

    guard
      let image = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage
    else {
      print("Info did not have the required UIImage for the Original Image")
      dismiss(animated: true)

      return
    }

    imageView.image = image

    // hide button while upload image
    takePictureButton.isHidden = true
    progressView.progress = 0.0
    progressView.isHidden = false
    activityIndicatorView.startAnimating()

    upload(
      image: image,
      progressCompletion: { [unowned self] percent in
      // progress handler with an updated percent
        self.progressView.setProgress(percent, animated: true)
      },
      completion: { [unowned self] tags, colors in
        // the completion handler executes when the upload finishes
        self.takePictureButton.isHidden = false
        self.progressView.isHidden = true
        self.activityIndicatorView.stopAnimating()
        self.tags = tags
        self.colors = colors

        // upload result
        self.performSegue(withIdentifier: "ShowResults", sender: self)
      }
    )

    dismiss(animated: true)
  }
}

// Networking calls
extension ViewController {
  func upload(
    image: UIImage,
    progressCompletion: @escaping (_ percent: Float) -> Void,
    completion: @escaping (_ tags: [String], _ colors: [PhotoColor]) -> Void
  ) {
    guard let imageData = image.jpegData(compressionQuality: 0.5) else {
      print("Could not get JPEG representation of UIImage")

      return
    }
    
    AF.upload(multipartFormData: { multipartFormData in
      multipartFormData.append(imageData, withName: "image", fileName: "image.jpg", mimeType: "image/jpeg")
    }, with: ImaggaRouter.upload)
    .uploadProgress(queue: .main, closure: { progress in
      progressCompletion(Float(progress.fractionCompleted))
    })
    .validate(statusCode: 200..<300)
    .responseJSON { response in
      switch response.result {
      case .failure(let error):
        guard let errorStr = error.errorDescription else { return }
        
        debugPrint(errorStr)
        
        completion([String](), [PhotoColor]())
      case .success:
        guard
          let responseJSON = response.value as? [String: Any],
          let result = responseJSON["result"] as? [String: Any],
          let uploadId = result["upload_id"] as? String
        else {
          print("Invalid information received from service")
          
          completion([String](), [PhotoColor]())

          return
        }
        
        print("Content uploaded with ID: \(uploadId)")
        
        self.downloadTags(contentID: uploadId) { tags in
          self.downloadColors(contentID: uploadId) { colors in
            completion(tags, colors)
          }
        }
      }
    }
  }

  func downloadTags(contentID: String, completion: @escaping ([String]) -> Void) {
    AF.request(ImaggaRouter.tags(contentID))
    .responseJSON { response in
      switch response.result {
      case .failure(let error):
        guard let errorStr = error.errorDescription else { return }
        
        debugPrint(errorStr)
        
        completion([String]())
      case .success:
        guard
          let responseJSON = response.value as? [String: Any],
          let result = responseJSON["result"] as? [String: Any],
          let tagsAndConfidences = result["tags"] as? [[String: Any]]
        else {
          print("Invalid information received from service")
          
          completion([String]())

          return
        }
                
        let tags = tagsAndConfidences.compactMap({ (dict) -> String? in
          guard let allLang = dict["tag"] as? [String: Any] else { return nil }
                    
          return allLang["en"] as? String
        })

        print("\(tags.count) tag(s) uploaded")
        
        completion(tags)
      }
    }
  }

  func downloadColors(contentID: String, completion: @escaping ([PhotoColor]) -> Void) {
    AF.request(ImaggaRouter.colors(contentID))
    .responseJSON { response in
      switch response.result {
      case .failure(let error):
        guard let errorStr = error.errorDescription else { return }
        
        debugPrint(errorStr)
        
        completion([PhotoColor]())
      case .success:
        guard
          let responseJSON = response.value as? [String: Any],
          let result = responseJSON["result"] as? [String: Any],
          let colors = result["colors"] as? [String: Any],
          let imageColors = colors["image_colors"] as? [[String: Any]]
        else {
          print("Invalid information received from service")
          
          completion([PhotoColor]())

          return
        }
                
        let photoColors = imageColors.compactMap({ (dict) -> PhotoColor? in
          guard
            let r = dict["r"] as? Int,
            let g = dict["g"] as? Int,
            let b = dict["b"] as? Int,
            let closestPaletteColor = dict["closest_palette_color"] as? String
          else {
            return nil
          }
          
          return PhotoColor(red: r, green: g, blue: b, colorName: closestPaletteColor)
        })
        
        print("\(photoColors.count) color(s) uploaded")
        
        completion(photoColors)
      }
    }
  }
}

// Helper function inserted by Swift 4.2 migrator.
private func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
  return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
private func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
	return input.rawValue
}
