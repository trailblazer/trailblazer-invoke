# frozen_string_literal: true

require_relative "lib/trailblazer/invoke/version"

Gem::Specification.new do |spec|
  spec.name = "trailblazer-invoke"
  spec.version = Trailblazer::Invoke::VERSION
  spec.authors = ["Nick Sutterer"]
  spec.email = ["apotonick@gmail.com"]

  spec.summary = "Implements the canonical invoke for operations."
  spec.homepage = "https://trailblazer.to"
  spec.required_ruby_version = ">= 2.5.0"
  spec.license = "LGPL-3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/trailblazer/trailblazer-invoke"
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "trailblazer-activity-dsl-linear", ">= 2.0.0", "< 2.1.0"

  spec.add_development_dependency "bundler" # DISCUSS: do we need this?
  spec.add_development_dependency "minitest-line"
  # spec.add_development_dependency "trailblazer-developer"
  spec.add_development_dependency "trailblazer-core-utils"
end
