# frozen_string_literal: true

require_relative "lib/segfault_bin/version"

Gem::Specification.new do |spec|
  spec.name = "segfault_bin"
  spec.version = SegfaultBin::VERSION
  spec.authors = ["Mika Peltomaa"]
  spec.email = ["mika@peltomaa.org"]

  spec.summary = "Error reporting for Rails. Companion to the Segfault Bin collector."
  spec.description = "Self-hosted error reporter for Rails. Captures unhandled exceptions, " \
    "builds rich payloads with stack traces and request context, and ships them " \
    "asynchronously to a Segfault Bin collector."
  spec.homepage = "https://github.com/intoloop/segfault_bin"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.0"
end
