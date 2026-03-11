import UIKit
import Flutter
import FirebaseCore
import FirebaseCrashlytics

@main
@objc class AppDelegate: FlutterAppDelegate {

  func log(_ message: String) {
    print("IOS_BOOT: \(message)")
    Crashlytics.crashlytics().log("IOS_BOOT: \(message)")
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    log("AppDelegate start")

    if FirebaseApp.app() == nil {
      log("Configuring Firebase")
      FirebaseApp.configure()
      log("Firebase configured")
    }

    Crashlytics.crashlytics().setCustomValue("ios_boot", forKey: "boot_phase")

    log("Registering Flutter plugins")
    GeneratedPluginRegistrant.register(with: self)
    log("Flutter plugins registered")

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    log("AppDelegate finished launch")

    return result
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    log("applicationDidBecomeActive")
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    log("applicationWillEnterForeground")
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    log("applicationDidEnterBackground")
  }
}