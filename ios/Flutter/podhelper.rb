platform :ios, '12.0'

# CocoaPods integration for Flutter
use_frameworks!
use_modular_headers!

def flutter_install_all_ios_pods(flutter_application_path)
  pod 'Flutter', :path => File.join(flutter_application_path, 'Flutter')
end