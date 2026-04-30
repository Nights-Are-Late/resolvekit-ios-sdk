Pod::Spec.new do |s|
  s.name             = 'ResolveKit'
  s.version          = '1.4.2'
  s.summary          = 'Embed AI resolution agents natively inside your iOS app'
  s.description      = <<-DESC
    ResolveKit is a Swift SDK for embedding LLM-driven agent chat experiences
    in iOS and macOS apps. The SDK connects your app to a ResolveKit backend
    over an HTTP/3-first session event stream, replays in-flight turns after
    reconnects, and dispatches tool calls to native Swift functions you define.
  DESC

  s.homepage         = 'https://resolvekit.app'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ResolveKit' => 'dev@resolvekit.app' }
  s.source           = { :git => 'https://github.com/resolve-kit/resolvekit-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '16.0'
  s.osx.deployment_target = '12.0'
  s.swift_version = '5.9'

  s.source_files = 'Sources/**/*.swift'
  s.exclude_files = 'Sources/ResolveKitCodegen/**'

  s.frameworks = 'Foundation', 'UIKit', 'SwiftUI'
end
