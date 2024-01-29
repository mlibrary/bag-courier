require "logger"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/remote_client"

module RemoteClientRoleTest
  def test_plays_remote_role
    assert_respond_to @role_player, :send_file
    assert_respond_to @role_player, :retrieve_file
    assert_respond_to @role_player, :retrieve_files
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

  def test_retrieve_files
    special_remote_path = File.join(@remote_path, "special")
    super_special_remote_path = File.join(special_remote_path, "super")
    FileUtils.mkdir(special_remote_path)
    FileUtils.mkdir(super_special_remote_path)
    add_test_file(special_remote_path)
    add_test_file(super_special_remote_path)

    special_local_path = File.join(@local_path, "special")
    super_special_local_path = File.join(special_local_path, "super")
    refute Dir.exist?(special_local_path)
    @remote_client.retrieve_files(local_path: @local_path, remote_path: "special")
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

class AwsS3RemoteClientTest < Minitest::Test
  include RemoteClientRoleTest

  def setup
    @bucket_name = "aptrust.receiving.someorg.edu"
    @region = "us-east-2"

    @client = RemoteClient::AwsS3RemoteClient.from_config(
      region: "us-east-2",
      bucket_name: @bucket_name
    )

    @role_player = @client

    @mock_bucket = Minitest::Mock.new
    @mock_object = Minitest::Mock.new
    @client_with_mock = RemoteClient::AwsS3RemoteClient.new(@mock_bucket)

    @test_dir = File.join(__dir__, "remote_test_aws")
    @local_path = File.join(@test_dir, "local")
    FileUtils.mkdir_p(@local_path)
  end

  def test_from_config
    assert_equal Aws::S3::Bucket, @client.bucket.class
    assert_equal @bucket_name, @client.bucket.name
  end

  def test_remote_text
    assert_equal(
      "AWS S3 remote location in bucket \"#{@bucket_name}\"",
      @client.remote_text
    )
  end

  def test_send_file_to_remote_root
    local_file_path = "/export/file.txt"

    @mock_bucket.expect(:object, @mock_object, ["file.txt"])
    @mock_object.expect(:upload_file, true, [local_file_path])

    @client_with_mock.send_file(local_file_path: local_file_path)
    @mock_bucket.verify
    @mock_object.verify
  end

  def test_send_file_to_remote_path
    local_file_path = "/export/file.txt"
    remote_path = "/special/"

    @mock_bucket.expect(:object, @mock_object, ["/special/file.txt"])
    @mock_object.expect(:upload_file, true, [local_file_path])

    @client_with_mock.send_file(
      local_file_path: local_file_path, remote_path: remote_path
    )
    @mock_bucket.verify
    @mock_object.verify
  end

  def test_retrieve_file
    remote_file_path = "/special/file.txt"
    local_dir_path = "/restore/"

    @mock_bucket.expect(:object, @mock_object, ["/special/file.txt"])
    @mock_object.expect(:download_file, true, ["/restore/file.txt"])

    @client_with_mock.retrieve_file(
      remote_file_path: remote_file_path,
      local_dir_path: local_dir_path
    )

    @mock_bucket.verify
    @mock_object.verify
  end

  def test_retrieve_file_with_no_key_error
    remote_file_path = "/special/file.txt"
    local_dir_path = "/export/"

    raise_error = proc do
      raise Aws::S3::Errors::NoSuchKey.new(
        "some context", "Object key does not exist"
      )
    end

    fake_object = Object.new
    fake_object.define_singleton_method(:download_file) do |path|
      "faking it!"
    end

    @mock_bucket.expect(:object, fake_object, [remote_file_path])
    fake_object.stub :download_file, raise_error do
      assert_raises RemoteClient::RemoteClientError do
        @client_with_mock.retrieve_file(
          remote_file_path: remote_file_path,
          local_dir_path: local_dir_path
        )
      end
    end
  end

  def test_retrieve_files
    remote_path = "/special/"

    @mock_bucket.expect(
      :objects,
      [{key: "/special/one.txt"}, {key: "/special/two.txt"}],
      [{prefix: remote_path}]
    )

    @client_with_mock.stub :retrieve_file, true do
      @client_with_mock.retrieve_files(local_path: @local_path, remote_path: remote_path)
    end

    assert Dir.exist?(File.join(@local_path, "special"))
    @mock_bucket.verify
  end

  def teardown
    FileUtils.rm_r(@test_dir)
  end
end
