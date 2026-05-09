# frozen_string_literal: true

require "rails/generators/base"

module SegfaultBin
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Copy a SegfaultBin initializer to config/initializers/segfault_bin.rb"

      def copy_initializer
        template "segfault_bin.rb", "config/initializers/segfault_bin.rb"
      end
    end
  end
end
