#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint stockfish.podspec' to validate before publishing.
#
#
require 'yaml'

pubspec = YAML.load(File.read(File.join(__dir__, '../pubspec.yaml')))

Pod::Spec.new do |s|
  s.name             = pubspec['name']
  s.version          = pubspec['version']
  s.summary          = pubspec['description']
  s.homepage         = pubspec['homepage']
  s.license          = { :file => '../LICENSE', :type => 'MIT' }
  s.author           = 'Arjan Aswal'
  s.source = { :git => pubspec['repository'], :tag => s.version.to_s }
  s.source_files = 'Classes/**/*', 'FlutterStockfish/*', 'Stockfish/src/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.exclude_files = 'Stockfish/src/incbin/UNLICENCE'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.ios.deployment_target  = '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }

  # Additional compiler configuration required for Stockfish
  s.library = 'c++'
  s.script_phase = {
    :execution_position => :before_compile,
    :name => 'Download nnue',
    :script => "[ -e 'nn-1111cefa1111.nnue' ] || curl --location --remote-name 'https://tests.stockfishchess.org/api/nn/nn-1111cefa1111.nnue'"
  }
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS[config=Debug]' => '$(inherited) -std=c++17 -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT',
    'OTHER_LDFLAGS[config=Debug]' => '$(inherited) -std=c++17 -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT',
    'OTHER_CPLUSPLUSFLAGS[config=Release]' => '$(inherited) -fno-exceptions -std=c++17 -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -flto=full',
    'OTHER_LDFLAGS[config=Release]' => '$(inherited) -fno-exceptions -std=c++17 -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -flto=full'
  }
end
