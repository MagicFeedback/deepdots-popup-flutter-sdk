require 'digest'
require 'fileutils'

# SDK nativo de Deepdots (KMP). Mismo zip y checksum que el paquete SPM
# (MagicFeedback/DeepdotsSDK-SPM); la versión tiene que coincidir con la de Package.swift.
DEEPDOTS_SDK_VERSION = '0.7.9'
DEEPDOTS_SDK_SHA256 = 'e7f6aeea192b566d4518fdc6395d0d11148dd2f8b4a11f732c2c5ae60fab43ab'
DEEPDOTS_SDK_URL = "https://github.com/MagicFeedback/DeepdotsSDK-SPM/releases/download/#{DEEPDOTS_SDK_VERSION}/DeepdotsSDK-#{DEEPDOTS_SDK_VERSION}.xcframework.zip"

# Flutter instala los plugins como pods locales (`:path`), y CocoaPods no ejecuta
# `prepare_command` en esos. Por eso el XCFramework se descarga aquí, al evaluar el podspec en
# `pod install`, y se comprueba su sha256 antes de descomprimirlo. Solo una vez por versión.
frameworks_dir = File.join(__dir__, 'deepdots_popups', 'Frameworks')
marker = File.join(frameworks_dir, ".version-#{DEEPDOTS_SDK_VERSION}")
unless File.exist?(marker)
  FileUtils.rm_rf(frameworks_dir)
  FileUtils.mkdir_p(frameworks_dir)
  zip = File.join(frameworks_dir, 'DeepdotsSDK.xcframework.zip')
  unless system('curl', '-fsSL', '--retry', '3', '-o', zip, DEEPDOTS_SDK_URL)
    raise "deepdots_popups: could not download #{DEEPDOTS_SDK_URL}"
  end
  actual = Digest::SHA256.file(zip).hexdigest
  if actual != DEEPDOTS_SDK_SHA256
    FileUtils.rm_rf(frameworks_dir)
    raise "deepdots_popups: checksum mismatch for DeepdotsSDK #{DEEPDOTS_SDK_VERSION} (got #{actual})"
  end
  system('unzip', '-q', '-o', zip, '-d', frameworks_dir) or raise 'deepdots_popups: could not unzip DeepdotsSDK'
  FileUtils.rm_f(zip)
  FileUtils.touch(marker)
end

Pod::Spec.new do |s|
  s.name             = 'deepdots_popups'
  s.version          = '1.0.1'
  s.summary          = 'Deepdots popups for Flutter, on top of the native Deepdots SDK.'
  s.description      = 'Flutter plugin that wraps the native Deepdots popup SDK (Android and iOS).'
  s.homepage         = 'https://github.com/MagicFeedback/deepdots-popup-flutter-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Deepdots' => 'support@deepdots.com' }
  s.source           = { :path => '.' }
  s.source_files = 'deepdots_popups/Sources/deepdots_popups/**/*'
  s.dependency 'Flutter'
  s.vendored_frameworks = 'deepdots_popups/Frameworks/DeepdotsSDK.xcframework'
  s.platform = :ios, '13.0'

  # Flutter.framework no trae i386, y el SDK nativo no trae x86_64 de simulador (solo Macs Intel).
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64' }
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.swift_version = '5.0'
end
