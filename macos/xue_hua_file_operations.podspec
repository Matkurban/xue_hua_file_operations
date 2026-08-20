#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint xue_hua_file_operations.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'xue_hua_file_operations'
  s.version          = '1.3.0'
  s.summary          = 'Cross-platform Flutter plugin for file operations.'
  s.description      = <<-DESC
Cross-platform Flutter plugin for picking files/directories, save-as, saving
to the gallery, and opening files with the system default app.
                       DESC
  s.homepage         = 'https://github.com/Matkurban/xue_hua_file_operations'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Matkurban' => 'https://github.com/Matkurban' }

  s.source           = { :path => '.' }
  s.source_files = 'xue_hua_file_operations/Sources/xue_hua_file_operations/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'xue_hua_file_operations_privacy' => ['xue_hua_file_operations/Sources/xue_hua_file_operations/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '11.0'
  s.frameworks = 'Photos'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
