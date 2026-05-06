require "aws-sdk-s3"

require_relative "../lib/remote_client"

class FakeTransferManagerForSingleRetrieval
  def download_file(destination, bucket:, **options)
    FileUtils.touch(destination)
  end
end

class FakeTransferManagerForNoKeyError
  def download_file(destination, bucket:, **options)
    raise Aws::S3::Errors::NoSuchKey.new(
      Seahorse::Client::RequestContext.new, "Object key does not exist"
    )
  end
end

class FakeTransferManagerForMultipartDownloadError
  def download_file(destination, bucket:, **options)
    raise Aws::S3::MultipartDownloadError.new("Your multi-part download failed, oh no!")
  end
end

class FakeTransferManagerForMultipartUploadError
  def upload_file(destination, bucket:, **options)
    raise Aws::S3::MultipartUploadError.new(
      "Your multi-part upload failed, oh no!", [Exception.new]
    )
  end
end

class FakeTransferManagerForRetrievalFromPath
  def download_directory(destination, bucket:, **options)
    prefix = options[:s3_prefix]
    directories = File.join(*[destination, prefix].compact)
    FileUtils.mkdir_p(directories)

    ["file1.txt", "file2.txt"].each do |filename|
      FileUtils.touch(File.join(directories, filename))
    end
  end
end

class FakeTransferManagerForRetrievalFromRoot
  def download_directory(destination, bucket:, **options)
    directories = File.join(destination, "child")
    FileUtils.mkdir_p(directories)

    ["file1.txt", "file2.txt"].each do |filename|
      FileUtils.touch(File.join(directories, filename))
    end
    FileUtils.touch(File.join(destination, "file3.txt"))
  end
end

class FakeTransferManagerForDirectoryDownloadError
  def download_directory(destination, bucket:, **options)
    raise Aws::S3::DirectoryDownloadError.new(
      "There was an error downloading a directory, oh no!", [Exception.new]
    )
  end
end

Rspec.shared_examples "a remote client" do
  it { is_expected.to respond_to(:remote_text) }
  it { is_expected.to respond_to(:send_file) }
  it { is_expected.to respond_to(:retrieve_file) }
  it { is_expected.to respond_to(:retrieve_from_path) }
end

describe RemoteClient::AwsS3RemoteClient do
  include_context "uses temp dir"

  before(:each) do
    @bucket = instance_double(Aws::S3::Bucket, name: "my-s3-bucket")
    @transfer_manager = instance_double(Aws::S3::TransferManager)
  end

  subject do
    described_class.new(@bucket, @transfer_manager)
  end
  it_behaves_like "a remote client"

  context "#from_config" do
    it "sets up an instance with the right classes" do
      @client = RemoteClient::AwsS3RemoteClient.from_config(
        region: "us-east-2",
        bucket_name: "aptrust.receiving.someorg.edu"
      )
      expect(@client.bucket.class).to eq(Aws::S3::Bucket)
      expect(@client.transfer_manager.class).to eq(Aws::S3::TransferManager)
      expect(@client.bucket.name).to eq("aptrust.receiving.someorg.edu")
    end
  end

  context "#update_config" do
    it "updates the AWS config with the right credentials" do
      access_key_id = "some-access-key"
      secret_access_key = "some-secret-key"
      RemoteClient::AwsS3RemoteClient.update_config(
        access_key_id: access_key_id,
        secret_access_key: secret_access_key
      )
      creds = Aws.config[:credentials]
      expect(creds.access_key_id).to eq(access_key_id)
      expect(creds.secret_access_key).to eq(secret_access_key)
    end
  end

  context "#remote_text" do
    it "returns the expected text" do
      expect(subject.remote_text).to eq('AWS S3 remote location in bucket "my-s3-bucket"')
    end
  end

  context "#send_file" do
    it "should call transfer manager with the correct arguments without remote path" do
      file_path = File.join(temp_dir, "file.txt")
      FileUtils.touch(file_path)
      expect(@transfer_manager).to receive(:upload_file).with(
        file_path,
        bucket: "my-s3-bucket",
        key: "file.txt",
        progress_callback: RemoteClient::AwsS3RemoteClient::UPLOAD_PROGRESS
      )
      subject.send_file(local_file_path: file_path)
    end

    it "should call transfer manager with the correct arguments with remote path" do
      file_path = File.join(temp_dir, "file.txt")
      FileUtils.touch(file_path)
      expect(@transfer_manager).to receive(:upload_file).with(
        file_path,
        bucket: "my-s3-bucket",
        key: "somewhere/file.txt",
        progress_callback: RemoteClient::AwsS3RemoteClient::UPLOAD_PROGRESS
      )
      subject.send_file(local_file_path: file_path, remote_path: "somewhere")
    end

    it "should raise a remote client error when multi-part upload error is encountered" do
      @transfer_manager = FakeTransferManagerForMultipartUploadError.new

      file_path = File.join(temp_dir, "file.txt")
      FileUtils.touch(file_path)
      expect {
        subject.send_file(local_file_path: file_path, remote_path: "somewhere")
      }.to raise_error(RemoteClient::RemoteClientError)
    end
  end

  context "#retrieve_file" do
    it "puts a file into the expected place" do
      @transfer_manager = FakeTransferManagerForSingleRetrieval.new

      subject.retrieve_file(remote_file_path: "file.txt", local_dir_path: temp_dir)
      expect(File.exist?(File.join(temp_dir, "file.txt"))).to eq(true)
    end

    it "throws a remote client error when no key exists" do
      @transfer_manager = FakeTransferManagerForNoKeyError.new

      expect {
        subject.retrieve_file(remote_file_path: "nosuchfile.txt", local_dir_path: temp_dir)
      }.to raise_error(RemoteClient::RemoteClientError)
    end

    it "throws a remote client error when multi-part download error is encountered" do
      @transfer_manager = FakeTransferManagerForMultipartDownloadError.new

      expect {
        subject.retrieve_file(remote_file_path: "file.txt", local_dir_path: temp_dir)
      }.to raise_error(RemoteClient::RemoteClientError)
    end

  end

  context "#retrieve_from_path" do
    it "puts the files (with their relative directory structure) into expected place" do
      @transfer_manager = FakeTransferManagerForRetrievalFromPath.new

      subject.retrieve_from_path(local_path: temp_dir, remote_path: "parent/child/here")
      expect(File.exist?("#{temp_dir}/here/file1.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/here/file2.txt")).to eq(true)
    end

    it "throws a remote client error when download directory error occurs" do
      @transfer_manager = FakeTransferManagerForDirectoryDownloadError.new

      expect {
        subject.retrieve_from_path(local_path: temp_dir, remote_path: "parent/child/here")
      }.to raise_error(RemoteClient::RemoteClientError)
    end

  end

  context "#retrieve_all" do
    it "puts all the files (with their relative directory structure) into expected place" do
      @transfer_manager = FakeTransferManagerForRetrievalFromRoot.new

      subject.retrieve_all(local_path: temp_dir)
      expect(File.exist?("#{temp_dir}/child/file1.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/child/file2.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/file3.txt")).to eq(true)
    end

    it "throws a remote client error when download directory error occurs" do
      @transfer_manager = FakeTransferManagerForDirectoryDownloadError.new

      expect { subject.retrieve_all(local_path: temp_dir) }.to raise_error(RemoteClient::RemoteClientError)
    end
  end
end

