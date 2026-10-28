import AVFoundation
import UIKit

/// Getting onto the iPhone Duo's rear display, as measured by ../duo_rear on
/// iOS 27.1: the private reserved scene accessory shows an app scene there
/// without the camera, but dim; the rear panel is bright only while a camera
/// session runs. Either way it lasts only while this app is full screen
/// inside: the accessory scene is hosted by the main scene.
enum Rear {
    static var bright: Bool {
        get { UserDefaults.standard.object(forKey: "bright") == nil || UserDefaults.standard.bool(forKey: "bright") }
        set { UserDefaults.standard.set(newValue, forKey: "bright") }
    }

    static func register(from vc: UIViewController) -> UISceneAccessoryRegistration {
        let config = UISceneConfiguration(name: "Rear", sessionRole: .windowApplication)
        config.delegateClass = RearSceneDelegate.self
        let sel = NSSelectorFromString("_reservedSceneAccessoryWithConfiguration:")
        if UISceneAccessory.responds(to: sel),
           let accessory = UISceneAccessory.perform(sel, with: config)?.takeUnretainedValue() as? UISceneAccessory {
            log("rear: reserved accessory")
            return vc.registerSceneAccessory(accessory)
        }
        // Gone in some later iOS: the public accessory needs the camera running.
        log("rear: no reserved accessory on this iOS; using the camera capture one")
        let camera = UISceneConfiguration(name: "Rear", sessionRole: .windowCameraCaptureAccessory)
        camera.delegateClass = RearSceneDelegate.self
        bright = true
        return vc.registerSceneAccessory(.cameraCapture(sceneConfiguration: camera))
    }
}

final class RearSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        log("rear: on, \(scene.screen.bounds.size)")
        let w = UIWindow(windowScene: scene)
        w.rootViewController = RearViewController()
        w.makeKeyAndVisible()
        window = w
    }

    func sceneDidDisconnect(_ scene: UIScene) { log("rear: off") }
}

/// The rear scene never rotates: it is drawn in the rear panel's own portrait
/// whichever way the phone is held. Held unfolded and upright, that is
/// sideways, so this turns the page itself to follow gravity.
///
/// Which way is up on a panel you look at from behind the main screen is
/// guessed, not measured: a long press on the rear turns the page a quarter
/// for the way the phone is held right now, and that is remembered.
final class RearViewController: UIViewController {
    private let magazine = MagazineView()
    private var held: UIDeviceOrientation = .portrait

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.paper
        view.addSubview(magazine)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let center = NotificationCenter.default
        center.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.follow(UIDevice.current.orientation)
        }
        center.addObserver(forName: Roast.changed, object: nil, queue: .main) { [weak self] _ in
            self?.magazine.page = Roast.shared.page
        }
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(turn)))
        magazine.page = Roast.shared.page
        follow(UIDevice.current.orientation)
    }

    deinit { UIDevice.current.endGeneratingDeviceOrientationNotifications() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        place(animated: false)
    }

    private static func quarters(for o: UIDeviceOrientation) -> Int {
        let key = "rear.quarters.\(o.rawValue)"
        if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.integer(forKey: key) % 4 }
        // Seen from behind, the main screen's left is the rear's right.
        switch o {
        case .landscapeLeft: return 3
        case .landscapeRight: return 1
        case .portraitUpsideDown: return 2
        default: return 0
        }
    }

    private func follow(_ o: UIDeviceOrientation) {
        // Lying flat says nothing about which edge is up: keep the last.
        guard o.isPortrait || o.isLandscape, o != held else { return }
        held = o
        log("rear: held \(o.rawValue), turning \(Self.quarters(for: o)) quarters")
        place(animated: true)
    }

    @objc private func turn(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let q = (Self.quarters(for: held) + 1) % 4
        UserDefaults.standard.set(q, forKey: "rear.quarters.\(held.rawValue)")
        log("rear: long press, held \(held.rawValue) now turns \(q) quarters")
        place(animated: true)
    }

    private func place(animated: Bool) {
        let q = Self.quarters(for: held)
        let size = view.bounds.size
        let apply = {
            self.magazine.transform = .identity
            self.magazine.bounds = CGRect(origin: .zero, size: q % 2 == 0 ? size : CGSize(width: size.height, height: size.width))
            self.magazine.center = CGPoint(x: size.width / 2, y: size.height / 2)
            self.magazine.transform = CGAffineTransform(rotationAngle: CGFloat(q) * .pi / 2)
            self.magazine.layoutIfNeeded()
        }
        animated ? UIView.animate(withDuration: 0.35, animations: apply) : apply()
    }
}

/// The cheapest capture session that still counts: smallest format, 1 fps,
/// every frame dropped. It only exists to make the rear panel bright.
final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = Camera()
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera")
    private var configured = false

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { log("camera: access denied, rear stays dim"); return }
            self.queue.async {
                self.configure()
                self.session.startRunning()
                log("camera: running=\(self.session.isRunning)")
            }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning(); log("camera: stopped") }
    }

    private func configure() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            log("camera: none usable")
            return
        }
        session.addInput(input)
        let formats = device.formats.filter { $0.mediaType == .video }
        func pixels(_ f: AVCaptureDevice.Format) -> Int32 {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width * d.height
        }
        if let format = formats.min(by: { pixels($0) < pixels($1) }),
           let range = format.videoSupportedFrameRateRanges.min(by: { $0.minFrameRate < $1.minFrameRate }),
           (try? device.lockForConfiguration()) != nil {
            device.activeFormat = format
            device.activeVideoMinFrameDuration = range.maxFrameDuration
            device.activeVideoMaxFrameDuration = range.maxFrameDuration
            device.unlockForConfiguration()
        }
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
    }
}
