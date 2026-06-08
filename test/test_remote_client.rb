require "bundler/setup"

require "aws-sdk-s3"
require "minitest/autorun"
require "minitest/pride"
require "sftp"

require_relative "test_helper"
require_relative "../lib/config"
require_relative "../lib/remote_client"

module RemoteClientRoleTest
  def test_plays_remote_role
    assert_respond_to @role_player, :send_file
    assert_respond_to @role_player, :retrieve_file
    assert_respond_to @role_player, :retrieve_from_path
  end
end

class FileSystemRemoteClientTest < Minitest::Test
  include RemoteClientRoleTest

  def setup
    @test_dir = File.join(__dir__, "remote_test_fs")
    @remote_path = File.join(@test_dir, "remote")
    @local_path = File.join(@test_dir, "local")
    @test_file_name = "test.txt"

    @role_player = RemoteClient::FileSystemRemoteClient.new(@remote_path)

    # Set up directories
    FileUtils.mkdir(@test_dir)
    FileUtils.mkdir(@remote_path)
    FileUtils.mkdir(@local_path)

    @remote_client = RemoteClient::FileSystemRemoteClient.new(@remote_path)
  end

  def add_test_file(dir_path)
    File.write(File.join(dir_path, @test_file_name), "test")
  end

  def test_remote_text
    assert_equal(
      "file system remote location at \"#{@remote_path}\"",
      @remote_client.remote_text
    )
  end

  def test_send_file
    add_test_file(@local_path)

    expected_remote_path = File.join(@remote_path, @test_file_name)
    refute File.exist?(expected_remote_path)
    @remote_client.send_file(local_file_path: File.join(@local_path, @test_file_name))
    assert File.exist?(expected_remote_path)
  end

  def test_send_file_to_remote_subdir
    special_remote_subdir = File.join(@remote_path, "special")
    FileUtils.mkdir(special_remote_subdir)
    add_test_file(@local_path)

    expected_remote_path = File.join(special_remote_subdir, @test_file_name)
    refute File.exist?(expected_remote_path)
    @remote_client.send_file(
      local_file_path: File.join(@local_path, @test_file_name),
      remote_path: "special"
    )
    assert File.exist?(expected_remote_path)
  end

  def test_retrieve_file
    add_test_file(@remote_path)

    refute File.exist?(File.join(@local_path, @test_file_name))
    @remote_client.retrieve_file(remote_file_path: @test_file_name, local_dir_path: @local_path)
    assert File.exist?(File.join(@local_path, @test_file_name))
  end

  def test_retrieve_from_path
    special_remote_path = File.join(@remote_path, "special")
    super_special_remote_path = File.join(special_remote_path, "super")
    FileUtils.mkdir(special_remote_path)
    FileUtils.mkdir(super_special_remote_path)
    add_test_file(special_remote_path)
    add_test_file(super_special_remote_path)

    special_local_path = File.join(@local_path, "special")
    super_special_local_path = File.join(special_local_path, "super")
    refute Dir.exist?(special_local_path)
    @remote_client.retrieve_from_path(local_path: @local_path, remote_path: "special")
    assert Dir.exist?(special_local_path)
    assert Dir.exist?(super_special_local_path)
    if Dir.exist?(special_local_path)
      assert File.exist?(File.join(special_local_path, @test_file_name))
    end
    if Dir.exist?(super_special_local_path)
      assert File.exist?(File.join(super_special_local_path, @test_file_name))
    end
  end

  def teardown
    FileUtils.rm_r(@test_dir)
  end
end

class SftpRemoteClientTest < Minitest::Test
  include RemoteClientRoleTest

  def setup
    @local_dir = "test_remote_sftp"
    @user = "someuser"
    @host = "something.org.edu"
    @key_path = "some/key/path"

    @client = RemoteClient::SftpRemoteClient.from_config(
      user: @user, host: @host, key_path: @key_path
    )
    @role_player = @client

    @mock_sftp_client = Minitest::Mock.new
    @remote_client_with_mock = RemoteClient::SftpRemoteClient.new(
      client: @mock_sftp_client, host: @host
    )
  end

  def test_from_config_sets_sftp_config
    config = SFTP.configuration
    assert_equal @host, config.host
    assert_equal @user, config.user
    assert_equal @key_path, config.key_path
  end

  def test_remote_text
    expected = "SFTP remote location at \"something.org.edu\""
    assert_equal expected, @client.remote_text
  end

  def test_send_file
    local_path = File.join(@local_dir, "file.txt")
    @mock_sftp_client.expect(:put, "some string output", [local_path, "/special"])
    @remote_client_with_mock.send_file(
      local_file_path: local_path, remote_path: "special"
    )
    @mock_sftp_client.verify
  end

  def test_send_file_to_root
    local_path = File.join(@local_dir, "file.txt")
    @mock_sftp_client.expect(:put, "some string output", [local_path, "/"])
    @remote_client_with_mock.send_file(local_file_path: local_path)
    @mock_sftp_client.verify
  end

  def test_retrieve_file
    remote_path = File.join("special", "file.txt")
    @mock_sftp_client.expect(:get, "some string output", ["/" + remote_path, @local_dir])
    @remote_client_with_mock.retrieve_file(
      remote_file_path: remote_path, local_dir_path: @local_dir
    )
    @mock_sftp_client.verify
  end

  def test_retrieve_from_path
    remote_path = File.join("/special")
    @mock_sftp_client.expect(:get_r, "some string output", [remote_path, @local_dir])
    @remote_client_with_mock.retrieve_from_path(
      remote_path: remote_path, local_path: @local_dir
    )
    @mock_sftp_client.verify
  end
end

class RemoteClientFactoryTest < Minitest::Test
  def test_factory_creates_file_system_variant
    remote_client = RemoteClient::RemoteClientFactory.from_config(
      type: :file_system,
      settings: Config::FileSystemRemoteConfig.new(
        remote_path: "path/to/something"
      )
    )
    assert remote_client.is_a?(RemoteClient::FileSystemRemoteClient)
  end

  def test_factory_creates_aws_s3_variant
    access_key_id = "some-access-key"
    secret_access_key = "some-secret-key"

    remote_client = RemoteClient::RemoteClientFactory.from_config(
      type: :aptrust,
      settings: Config::AptrustAwsRemoteConfig.new(
        region: "us-east-2",
        receiving_bucket: "aptrust.receiving.someorg.edu",
        restore_bucket: "aptrust.restore.someorg.edu",
        access_key_id: access_key_id,
        secret_access_key: secret_access_key
      )
    )
    assert remote_client.is_a?(RemoteClient::AwsS3RemoteClient)

    creds = Aws.config[:credentials]
    assert_equal access_key_id, creds.access_key_id
    assert_equal secret_access_key, creds.secret_access_key
  end

  def test_factory_creates_sftp_variant
    remote_client = RemoteClient::RemoteClientFactory.from_config(
      type: :sftp,
      settings: Config::SftpRemoteConfig.new(
        user: "someuser",
        host: "something.org.edu",
        key_path: "some/key/path"
      )
    )
    assert remote_client.is_a?(RemoteClient::SftpRemoteClient)
  end
end
