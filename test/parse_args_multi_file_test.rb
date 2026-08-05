# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../mdtosendy'

class ParseArgsMultiFileTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @a = File.join(@dir, 'a.md')
    @b = File.join(@dir, 'b.md')
    File.write(@a, "# A\n")
    File.write(@b, "# B\n")
    @old_argv = ARGV.dup
  end

  def teardown
    ARGV.replace(@old_argv)
    FileUtils.remove_entry(@dir)
  end

  def test_keeps_all_file_arguments
    ARGV.replace(['--preview', @a, @b])
    parsed = parse_args
    assert_equal true, parsed[:flags][:preview]
    assert_equal [@a, @b], parsed[:markdown_files]
    refute parsed.key?(:markdown_file)
  end

  def test_expands_glob_argument
    ARGV.replace([File.join(@dir, '*.md')])
    parsed = parse_args
    assert_equal [@a, @b].sort, parsed[:markdown_files].sort
  end
end
