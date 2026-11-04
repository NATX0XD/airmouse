Pod::Spec.new do |s|
  s.name           = 'AirMouseDiscovery'
  s.version        = '1.0.0'
  s.summary        = 'Bonjour browser for _airmouse._tcp + proximity sensor'
  s.description    = 'Finds AirMouse Macs on the local network and resolves them to host and port.'
  s.license        = 'MIT'
  s.author         = 'AirMouse'
  s.homepage       = 'https://example.com/airmouse'
  s.platforms      = { :ios => '16.4' }
  s.swift_version  = '5.9'
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  s.frameworks = 'Network', 'CoreBluetooth', 'UIKit', 'SceneKit'

  s.source_files = "**/*.{h,m,swift}"
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }
end
