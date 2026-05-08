# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe SegfaultBin::FrameBuilder do
  let(:tmpdir) { Dir.mktmpdir("sfb-frames") }
  after { FileUtils.remove_entry(tmpdir) }

  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.app_dirs_pattern = tmpdir
    end
  end

  describe "with backtrace_locations" do
    let(:exception) { raise_from_fixture(tmpdir) }

    it "extracts source context for in_app frames" do
      frames = described_class.new(exception, config).build
      target = frames.find { |f| f[:abs_path].end_with?("fixture.rb") }

      expect(target).to include(in_app: true)
      expect(target[:context_line]).to include("raise")
      expect(target[:pre_context]).to be_an(Array)
      expect(target[:post_context]).to be_an(Array)
    end

    it "marks frames outside the app root as not in_app" do
      other_config = SegfaultBin::Configuration.new.tap { |c| c.app_dirs_pattern = "/nowhere" }
      frames = described_class.new(exception, other_config).build
      expect(frames.map { |f| f[:in_app] }).to all(be false)
    end
  end

  it "falls back to backtrace strings when locations are absent" do
    real_root = File.realpath(tmpdir)
    err = StandardError.new("x")
    err.set_backtrace(["#{real_root}/app.rb:42:in `do_thing'"])
    frames = described_class.new(err, config).build

    expect(frames.first).to include(
      filename: "#{real_root}/app.rb",
      lineno: 42,
      function: "do_thing",
      in_app: true
    )
  end

  def raise_from_fixture(dir)
    path = File.join(dir, "fixture.rb")
    File.write(path, <<~RUBY)
      module SegfaultBinFixture
        def self.boom
          # padding line 1
          # padding line 2
          # padding line 3
          # padding line 4
          # padding line 5
          raise "boom from fixture"
        end
      end
    RUBY
    load path
    SegfaultBinFixture.boom
  rescue => e
    e
  end
end
