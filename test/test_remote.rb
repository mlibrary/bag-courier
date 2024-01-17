require "logger"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/remote"

module RemoteRoleTest
  def test_plays_remote_role
    assert_respond_to @role_player, :send_file
    assert_respond_to @role_player, :retrieve_file
    assert_respond_to @role_player, :retrieve_dir
  end
end

class FileSystemRemoteTest < Minitest::Test
  include RemoteRoleTest

  def setup
    test_dir = File.join(__dir__, "remote_test")
    @remote_path = File.join(test_dir, "remote")
    @local_path = File.join(test_dir, "local")
    @test_file_name = "test.txt"

    @role_player = Remote::FileSystemRemote.new(@remote_path)

    # Reset directories
    FileUtils.rm_r(test_dir) if Dir.exist?(test_dir)
    FileUtils.mkdir(test_dir)
    FileUtils.mkdir(@remote_path)
    FileUtils.mkdir(@local_path)

    @remote = Remote::FileSystemRemote.new(@remote_path)
  end

  def add_test_file(dir_path)
    File.write(File.join(dir_path, @test_file_name), "test")
  end

  def test_send_file
    add_test_file(@local_path)

    expected_remote_path = File.join(@remote_path, @test_file_name)
    refute File.exist?(expected_remote_path)
    @remote.send_file(local_file_path: File.join(@local_path, @test_file_name))
    assert File.exist?(expected_remote_path)
  end

  def test_send_file_to_remote_subdir
    special_remote_subdir = File.join(@remote_path, "special")
    FileUtils.mkdir(special_remote_subdir)
    add_test_file(@local_path)

    expected_remote_path = File.join(special_remote_subdir, @test_file_name)
    refute File.exist?(expected_remote_path)
    @remote.send_file(
      local_file_path: File.join(@local_path, @test_file_name),
      remote_dir_path: "special"
    )
    assert File.exist?(expected_remote_path)
  end

  def test_retrieve_file
    add_test_file(@remote_path)

    refute File.exist?(File.join(@local_path, @test_file_name))
    @remote.retrieve_file(remote_file_path: @test_file_name, local_dir_path: @local_path)
    assert File.exist?(File.join(@local_path, @test_file_name))
  end

  def test_retrieve_dir
    special_remote_subdir = File.join(@remote_path, "special")
    FileUtils.mkdir(special_remote_subdir)
    add_test_file(special_remote_subdir)

    special_local_dir = File.join(@local_path, "special")
    refute Dir.exist?(special_local_dir)
    @remote.retrieve_dir(local_dir_path: @local_path, remote_dir_path: "special")
    assert Dir.exist?(special_local_dir)
    if Dir.exist?(special_local_dir)
      assert File.exist?(File.join(special_local_dir, @test_file_name))
    end
  end
end
