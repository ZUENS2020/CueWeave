#!/usr/bin/env ruby
require "json"
require "open3"

# Native SwiftUI appearance depends on the linked SDK, not just the runtime OS.
module MacOSBuildGate
  CONFIG = JSON.parse(File.read(File.join(__dir__, "macos-toolchain.json"))).freeze

  def self.verify_toolchain!(xcode, sdk)
    version = xcode[/^Xcode (\S+)$/, 1]
    raise "Expected Xcode #{CONFIG.fetch('xcode')}, got #{version.inspect}" unless version == CONFIG.fetch("xcode")
    raise "Expected macOS SDK #{CONFIG.fetch('sdk')}, got #{sdk.strip.inspect}" unless sdk.strip == CONFIG.fetch("sdk")
  end

  def self.verify_binary!(load_commands)
    builds = load_commands.split(/^Load command \d+\s*$/).select { |block| block.match?(/^\s*cmd LC_BUILD_VERSION\s*$/) }
    raise "Mach-O LC_BUILD_VERSION is missing" if builds.empty?

    builds.each do |block|
      fields = block.scan(/^\s*(platform|minos|sdk)\s+(\S+)/).to_h
      { "platform" => "1", "minos" => CONFIG.fetch("minimumOS"), "sdk" => CONFIG.fetch("sdk") }.each do |key, expected|
        actual = fields[key]
        raise "Mach-O #{key}: expected #{expected}, got #{actual.inspect}" unless actual == expected
      end
    end
    builds.length
  end

  def self.capture!(*command)
    output, error, status = Open3.capture3(*command)
    raise "#{command.first} failed: #{error.strip}" unless status.success?
    output
  end

  def self.main(arguments)
    if arguments.length == 2 && arguments.first == "--binary"
      slices = verify_binary!(capture!("xcrun", "otool", "-l", arguments.last))
      puts "Verified #{slices} Mach-O slice(s): macOS SDK #{CONFIG.fetch('sdk')}, minimum macOS #{CONFIG.fetch('minimumOS')}"
    elsif arguments.empty?
      xcode = capture!("xcodebuild", "-version")
      sdk = capture!("xcrun", "--sdk", "macosx", "--show-sdk-version")
      verify_toolchain!(xcode, sdk)
      puts "#{xcode.strip}\nmacOS SDK #{sdk.strip}"
    else
      raise "Usage: ruby scripts/check-macos-toolchain.rb [--binary /path/to/CueWeave]"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MacOSBuildGate.main(ARGV)
  rescue StandardError => error
    warn "macOS build gate: #{error.message}"
    exit 1
  end
end
