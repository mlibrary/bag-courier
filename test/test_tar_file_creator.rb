require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/tar_file_creator"

class TarFileCreatorTest < Minitest::Test
  include TarFileCreator

  def add_data_file
    File.write(
      File.join(@data_dir_path, "something.txt"),
      "Something to be preserved"
    )
  end

  def setup
    @test_dir_path = File.join(__dir__, "tar_test")
    @data_dir_path = File.join(@test_dir_path, "test")
    @file_path = File.join(@test_dir_path, "test.tar")
    FileUtils.rm_r(@test_dir_path) if Dir.exist?(@test_dir_path)
    FileUtils.mkdir_p(@data_dir_path)

    File.write(
      File.join(@data_dir_path, "something.txt"),
      "Something to be preserved"
    )
  end

  def create_file
    TarFileCreator.setup.create(
      src_dir_path: @data_dir_path,
      dest_file_path: @file_path
    )
  end

  def test_create
    create_file
    assert File.exist?(@file_path)
  end

  def test_open
    create_file
    FileUtils.rm_r(@data_dir_path)

    TarFileCreator.setup.open(
      src_file_path: @file_path,
      dest_dir_path: @test_dir_path
    )

    assert Dir.exist?(@data_dir_path)
    assert File.exist?(File.join(@data_dir_path, "something.txt"))
  end

  def test_raises_error
    assert_raises TarFileCreatorError do
      TarFileCreator.setup.create(
        src_dir_path: File.join("something", "nonexistent_dir"),
        dest_file_path: @file_path
      )
    end
  end

  def test_create_if_dest_in_src
    assert_raises TarFileCreatorError do
      TarFileCreator.setup.create(
        src_dir_path: @data_dir_path,
        dest_file_path: File.join(@data_dir_path, "test")
      )
    end
  end
end
