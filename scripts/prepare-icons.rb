#!/usr/bin/env ruby
# Native asset conversion only. This script never builds or launches the application.
require 'fileutils'
require 'tmpdir'
require 'digest'
require 'json'

repo = File.expand_path('..', __dir__)
source = File.join(repo, 'apps/shared/branding/cueweave-suzuka-light-v2.png')
icns = File.join(repo, 'apps/macos/Resources/CueWeaveSuzuka.icns')
ico = File.join(repo, 'apps/windows/CueWeave.Windows/Assets/CueWeaveSuzuka.ico')
previews = File.join(repo, 'apps/shared/branding/previews')
manifest = File.join(repo, 'apps/shared/branding/icon-manifest.json')
sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]

def png_size(bytes)
  abort 'Invalid PNG signature' unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)
  bytes.byteslice(16, 8).unpack('N2')
end

master = File.binread(source)
dimensions = png_size(master)
abort 'Master must be square and at least 1024 pixels' unless dimensions[0] == dimensions[1] && dimensions[0] >= 1024
abort 'Master must be RGB or RGBA' unless [2, 6].include?(master.getbyte(25))
if ARGV == ['--write']
  Dir.mktmpdir('cueweave-icons-') do |temp|
    (sizes + [512, 1024]).uniq.each do |size|
      output = File.join(temp, "#{size}.png")
      abort "sips failed at #{size}px" unless system('/usr/bin/sips', '-z', size.to_s, size.to_s, source, '--out', output)
    end
    iconset = File.join(temp, 'CueWeaveSuzuka.iconset')
    FileUtils.mkdir_p(iconset)
    [16, 32, 128, 256, 512].each do |size|
      FileUtils.cp(File.join(temp, "#{size}.png"), File.join(iconset, "icon_#{size}x#{size}.png"))
      FileUtils.cp(File.join(temp, "#{size * 2}.png"), File.join(iconset, "icon_#{size}x#{size}@2x.png"))
    end
    staged_icns = File.join(temp, 'CueWeaveSuzuka.icns')
    abort 'iconutil failed' unless system('/usr/bin/iconutil', '-c', 'icns', iconset, '-o', staged_icns)
    images = sizes.map { |size| File.binread(File.join(temp, "#{size}.png")) }
    offset = 6 + sizes.length * 16
    directory = sizes.zip(images).map do |size, png|
      dimension = size == 256 ? 0 : size
      entry = [dimension, dimension, 0, 0, 1, 32, png.bytesize, offset].pack('C4v2V2')
      offset += png.bytesize
      entry
    end.join
    FileUtils.mkdir_p([File.dirname(icns), File.dirname(ico), previews])
    FileUtils.cp(staged_icns, icns)
    File.binwrite(ico, [0, 1, sizes.length].pack('v3') + directory + images.join)
    [16, 32, 64, 128].each { |size| FileUtils.cp(File.join(temp, "#{size}.png"), File.join(previews, "#{size}.png")) }
  end
  paths = [source, icns, ico] + [16, 32, 64, 128].map { |size| File.join(previews, "#{size}.png") }
  hashes = paths.to_h { |path| [path.delete_prefix(repo + '/'), Digest::SHA256.file(path).hexdigest] }
  File.write(manifest, JSON.pretty_generate(hashes) + "\n")
elsif ARGV != ['--check']
  abort 'Usage: ruby scripts/prepare-icons.rb --write | --check'
end

JSON.parse(File.read(manifest)).each do |relative, hash|
  abort "Icon assets changed; regenerate: #{relative}" unless Digest::SHA256.file(File.join(repo, relative)).hexdigest == hash
end

data = File.binread(ico)
abort 'Invalid ICO header' unless data.byteslice(0, 6).unpack('v3') == [0, 1, sizes.length]
sizes.each_with_index do |size, index|
  width, height, _, _, planes, bits, length, offset = data.byteslice(6 + index * 16, 16).unpack('C4v2V2')
  dimension = size == 256 ? 0 : size
  abort 'Invalid ICO directory' unless width == dimension && height == dimension && planes == 1 && bits == 32
  abort 'ICO image lies outside the file' unless offset >= 6 + sizes.length * 16 && offset + length <= data.bytesize
  abort 'ICO image dimensions mismatch' unless png_size(data.byteslice(offset, length)) == [size, size]
end
data = File.binread(icns)
abort 'Invalid ICNS header/length' unless data.byteslice(0, 4) == 'icns' && data.byteslice(4, 4).unpack1('N') == data.bytesize
types = []; offset = 8
while offset < data.bytesize
  type, length = data.byteslice(offset, 8).unpack('a4N')
  abort 'Invalid ICNS element length' if length < 8 || offset + length > data.bytesize
  types << type; offset += length
end
abort 'ICNS lacks standard/Retina artwork' unless %w[ic07 ic08 ic09 ic10 ic11 ic12].all? { |type| types.include?(type) }
puts "Icon resources verified: ICO #{sizes.join('/')} px; ICNS standard + Retina up to 1024 px."
