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

failed = 0
todo.each_with_index do |doc, i|
  label = "#{doc.name}#{" #{doc.version}" if doc.version.present?}"
  target = File.join(store, doc.path)
  staging = "#{target}.part"
  archive = nil
  begin
    archive = Docs::Archive.download("https://downloads.devdocs.io/#{doc.path}.tar.gz")
    Docs::Archive.unpack(archive, staging)
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
Sprockets::Manifest.new(App.sprockets.index, App.assets_manifest_path).compile('docs.js')
count = JSON.parse(File.read(App.docs_manifest_path)).length
puts "[devdocs] #{count} documentation set(s) installed; #{failed} download(s) failed"
abort '[devdocs] no documentation installed' if count.zero?
