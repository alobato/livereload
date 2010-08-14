#!/usr/bin/ruby -rubygems

# http://gist.github.com/484894

# Replacement for "livereload" gem for working with Rails
#
# Dependencies:
#   $ gem install mislav-rspactor em-websocket json haml

# uncomment to force loading the correct rspactor version
# gem 'mislav-rspactor', '~> 0.4.0'
require 'rspactor'
require 'em-websocket'
require 'json'
require 'sass/plugin'

API_VERSION = '1.3'

web_sockets = []
debug = !!ARGV.delete('-D')
dirs = ARGV.empty?? [Dir.pwd] : ARGV

compass_config = "./config/compass.rb"

if File.exists? compass_config
  # $ sudo /usr/bin/gem install compass
  require 'compass'
  Compass.add_project_configuration(compass_config)
  Compass.configure_sass_plugin!
  Compass.handle_configuration_change!
else
  Sass::Plugin.add_template_location(Dir.pwd + '/app/styles')
end

extensions = %w[html erb haml sass scss css js rb yml]

listener = RSpactor::Listener.new(:extensions => extensions, :relative_paths => false) { |files|
  for file in files
    case file
    when %r{/app/.+\.(erb|haml)$}, %r{/app/helpers/.+\.rb$}, # application view code
        %r{/public/.+\.(css|js|html)$}, # static assets
        %r{/config/locales/.+\.yml$} # translation files
      data = ['refresh', { :path => file, :apply_js_live  => false, :apply_css_live => true }].to_json
      puts data if debug
      # send it to the browser!
      web_sockets.each { |ws| ws.send(data) }
    when %r{\.s[ac]ss$}
      puts "Regenerating CSS stylesheets..." if debug
      Sass::Plugin.update_stylesheets
    else
      puts "Unhandled change: #{file}" if debug
    end
  end
}

Sass::Plugin.on_updating_stylesheet do |template, css|
  # We notify the listener that the stylesheet file changed for sure.
  # Because the filesystem can't know modification time in milliseconds,
  # this prevents FSEvents handler from thinking the file didn't change.
  listener.force_changed << File.expand_path(css, Dir.pwd)
end

EventMachine.run do
  puts "LiveReload is waiting for a browser to connect."
  EventMachine::WebSocket.start(:host => '0.0.0.0', :port => '35729', :debug => debug) do |ws|
    ws.onopen do
      begin
        puts "Browser connected."
        ws.send "!!ver:#{API_VERSION}"
        web_sockets << ws
      rescue
        puts $!
        puts $!.backtrace
      end
    end
  
    ws.onmessage do |msg|
      puts "Browser URL: #{msg}"
    end
  
    ws.onclose do
      web_sockets.delete ws
      puts "Browser disconnected."
    end
  end
  
  puts "Starting file watcher for directories: #{dirs.inspect}"
  listener.start(dirs)
  
  # Disable the RubyCocoa thread hook as apparently Laurent did not apply the
  # thread patches to the OS X system Ruby
  ENV['RUBYCOCOA_THREAD_HOOK_DISABLE'] = 'kampai'
  
  Thread.new { OSX.CFRunLoopRun }
end
