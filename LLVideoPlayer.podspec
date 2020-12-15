Pod::Spec.new do |s|
  s.name             = 'LLVideoPlayer'
  s.version          = '1.2.7'
  s.summary          = 'A low level, flexible video player based on AVPlayer for iOS.'

  s.description      = <<-DESC
LLVideoPlayer is a low level video player which is simple and easy to extend.
Support lazy loading，limit download size.
                       DESC

  s.homepage         = 'https://github.com/huangguiyang/LLVideoPlayer'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'mario' => 'guiyang.huang@gmail.com' }
  s.source           = { :git => 'https://github.com/li6185377/LLVideoPlayer.git', :branch => 'master' }

  s.ios.deployment_target = '9.0'

  s.public_header_files = 'LLVideoPlayer/*.h'
  s.source_files = 'LLVideoPlayer/*.{m,h}'

  s.subspec 'CacheSupport' do |ss|
	ss.source_files = 'LLVideoPlayer/CacheSupport'
  end

  s.frameworks = 'QuartzCore', 'MediaPlayer', 'AVFoundation'
end
