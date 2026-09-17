Pod::Spec.new do |s|
  s.name = 'PhotosOriginal'
  s.version = '0.1.0'
  s.summary = 'PhoneTransfer originals plugin'
  s.license = 'MIT'
  s.homepage = 'https://example.local/phonetransfer'
  s.author = 'PhoneTransfer'
  s.source = { :git => 'https://example.local/phonetransfer.git', :tag => s.version.to_s }
  s.platform = :ios, '14.0'
  s.source_files = 'ios/Plugin/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
end
