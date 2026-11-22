# frozen_string_literal: true
#
# Runs before Puma on every boot:
# 1. downloads the documentation sets named in DEVDOCS_DOCS that aren't on the volume yet
#    (and refreshes every installed set once DEVDOCS_REFRESH_DAYS have passed),
# 2. rebuilds the docs catalog and the docs.js asset that ships it to browsers.
# Sets removed from DEVDOCS_DOCS stay installed; delete their folder on the volume to drop them.

ENV['RACK_ENV'] = 'production'
Dir.chdir(File.expand_path('..', __dir__))
$LOAD_PATH.unshift 'lib'
$stdout.sync = true

require 'docs'
require 'fileutils'

DEFAULT_DOCS = 'css dom html http javascript'
DOWNLOADS_URL = ENV.fetch('DEVDOCS_DOWNLOADS_URL', 'https://downloads.devdocs.io').chomp('/')
store = Docs.store_path
FileUtils.mkdir_p(store)

names = (ENV['DEVDOCS_DOCS'].to_s.strip.empty? ? DEFAULT_DOCS : ENV['DEVDOCS_DOCS']).split(/[\s,]+/).reject(&:empty?)
wanted = if names.map(&:downcase) == ['all']
  Docs.all_versions
else
  names.flat_map do |name|
    slug, version = name.downcase.split(/@|~/, 2)
    base = Docs.all.find { |doc| doc.slug == slug }
    unless base
      puts "[devdocs] unknown documentation \"#{name}\", skipped (see https://devdocs.io/ for names)"
      next []
    end
    next [base.versions.first] if version.nil? || version.empty?
    match = base.versions.find { |doc| doc.version == version || doc.version_slug == version }
    puts "[devdocs] unknown version \"#{name}\", skipped" unless match
    match ? [match] : []
  end
end

installed = ->(doc) { File.exist?(File.join(store, doc.path, 'index.json')) }
stamp = File.join(store, '.last-refresh')
refresh_days = Integer(ENV.fetch('DEVDOCS_REFRESH_DAYS', '30'), exception: false) || 30
refresh = refresh_days.positive? && File.exist?(stamp) && File.mtime(stamp) < Time.now - refresh_days * 86_400

todo = refresh ? (wanted + Docs.installed).uniq : wanted.reject(&installed)
puts "[devdocs] #{wanted.length} wanted, #{todo.length} to download#{' (monthly refresh)' if refresh}"

require 'open3'

# The published archives are made on macOS and carry extended attributes and
# AppleDouble (._*) files; Railway volumes can't store those xattrs, so skip them.
def unpack(archive, target)
  FileUtils.rm_rf(target)
  FileUtils.mkdir_p(target)
  out, status = Open3.capture2e('bsdtar', '-xf', archive, '-C', target, '--no-xattrs', '--no-acls',
                                '--no-fflags', '--no-same-owner', '--exclude', '._*')
  return if status.success?
  raise "bsdtar exited #{status.exitstatus}: #{out.lines.first(3).join.strip}"
end

failed = 0
todo.each_with_index do |doc, i|
  label = "#{doc.name}#{" #{doc.version}" if doc.version.present?}"
  target = File.join(store, doc.path)
  staging = "#{target}.part"
  archive = nil
  begin
    archive = Docs::Archive.download("#{DOWNLOADS_URL}/#{doc.path}.tar.gz")
    unpack(archive, staging)
    FileUtils.rm_rf(target)
    File.rename(staging, target)
    puts "[devdocs] (#{i + 1}/#{todo.length}) #{label} OK"
  rescue StandardError => e
    failed += 1
    FileUtils.rm_rf(staging)
    puts "[devdocs] (#{i + 1}/#{todo.length}) #{label} FAILED (#{e.class}: #{e.message})"
  ensure
    FileUtils.rm_f(archive) if archive
  end
end
FileUtils.touch(stamp) if failed.zero? && (refresh || !File.exist?(stamp))

# Loading the app regenerates public/docs/docs.json from what is installed;
# docs.js embeds that catalog, so recompile it before Puma starts.
require 'app'
catalog = JSON.parse(File.read(App.docs_manifest_path))
count = catalog.length
abort '[devdocs] no documentation installed' if count.zero?

# A new browser enables the sets named in DEVDOCS_DOCS (upstream's fixed default
# list would leave nothing enabled when other sets are installed).
installed_slugs = catalog.map { |doc| doc['slug'] }
wanted_all = names.map(&:downcase) == ['all']
defaults = (wanted_all ? DEFAULT_DOCS.split : wanted.map(&:slug)) & installed_slugs
defaults = installed_slugs.first(20) if defaults.empty?
App.set :default_docs, defaults

# config.js embeds the defaults and a timestamp, so compile it only when the
# defaults change (the stamp lives in the image, so a new deploy recompiles).
assets = ['docs.js']
defaults_stamp = File.join(App.assets_path, '.selfhost-default-docs')
assets << 'app/config.js' unless File.exist?(defaults_stamp) && File.read(defaults_stamp) == defaults.join(' ')
Sprockets::Manifest.new(App.sprockets.index, App.assets_manifest_path).compile(*assets)
File.write(defaults_stamp, defaults.join(' '))
puts "[devdocs] enabled by default for new visitors: #{defaults.join(' ')}"
puts "[devdocs] #{count} documentation set(s) installed; #{failed} download(s) failed"
