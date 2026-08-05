# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../mdtosendy'

class ResolveMarkdownFilesTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @a = File.join(@dir, 'a.md')
    @b = File.join(@dir, 'b.md')
    @c = File.join(@dir, 'c.txt')
    File.write(@a, "# A\n")
    File.write(@b, "# B\n")
    File.write(@c, "not md\n")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_literal_paths_preserve_order
    result = resolve_markdown_files([@b, @a])
    assert_equal [@b, @a], result
  end

  def test_glob_expands_sorted_within_arg
    pattern = File.join(@dir, '*.md')
    result = resolve_markdown_files([pattern])
    assert_equal [@a, @b].sort, result
  end

  def test_mixed_literal_and_glob_preserve_arg_order
    assert_equal [@b, @a, @b], resolve_markdown_files([@b, File.join(@dir, '*.md')])
  end

  def test_missing_literal_exits
    err = assert_raises(SystemExit) do
      resolve_markdown_files([File.join(@dir, 'missing.md')])
    end
    assert_equal 1, err.status
  end

  def test_empty_glob_exits
    err = assert_raises(SystemExit) do
      resolve_markdown_files([File.join(@dir, 'no-match-*.md')])
    end
    assert_equal 1, err.status
  end

  def test_directory_literal_exits
    err = assert_raises(SystemExit) do
      resolve_markdown_files([@dir])
    end
    assert_equal 1, err.status
  end

  def test_glob_excludes_directories
    subdir = File.join(@dir, 'sub.md')
    FileUtils.mkdir_p(subdir)
    pattern = File.join(@dir, '*.md')
    result = resolve_markdown_files([pattern])
    assert_equal [@a, @b].sort, result
  end

  def test_glob_matching_only_directory_exits
    dir_only = Dir.mktmpdir
    subdir = File.join(dir_only, 'sub.md')
    FileUtils.mkdir_p(subdir)
    err = assert_raises(SystemExit) do
      resolve_markdown_files([File.join(dir_only, '*.md')])
    end
    assert_equal 1, err.status
  ensure
    FileUtils.remove_entry(dir_only) if dir_only
  end
end
