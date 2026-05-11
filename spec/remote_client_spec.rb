require "aws-sdk-s3"

require_relative "../lib/remote_client"

FakeObject = Struct.new(:key, keyword_init: true)

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
    described_class.new(bucket: @bucket, transfer_manager: @transfer_manager)
  end
  it_behaves_like "a remote client"

  context "#from_config" do
    it "sets up an instance using config values" do
      expect {
        RemoteClient::AwsS3RemoteClient.from_config(
          region: "us-east-2",
          bucket_name: "aptrust.receiving.someorg.edu"
        )
      }.not_to raise_error
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
    it "calls transfer manager with the correct arguments without remote path" do
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

    it "calls transfer manager with the correct arguments with remote path" do
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

    it "throws a remote client error when multi-part upload error is encountered" do
      expect(@transfer_manager).to receive(:upload_file) {
        raise Aws::S3::MultipartUploadError.new(
          "Your multi-part upload failed, oh no!", [Exception.new]
        )
      }

      file_path = File.join(temp_dir, "file.txt")
      FileUtils.touch(file_path)
      expect {
        subject.send_file(local_file_path: file_path, remote_path: "somewhere")
      }.to raise_error(RemoteClient::RemoteClientError)
    end
  end

  context "#retrieve_file" do
    it "puts a file into the expected place" do
      file_path = File.join(temp_dir, "file.txt")
      expect(@transfer_manager).to receive(:download_file).with(
        file_path, bucket: "my-s3-bucket", key: "file.txt"
      ) { |destination|
        FileUtils.touch(destination)
      }

      subject.retrieve_file(remote_file_path: "file.txt", local_dir_path: temp_dir)
      expect(File.exist?(File.join(temp_dir, "file.txt"))).to eq(true)
    end

    it "throws a remote client error when no key exists" do
      expect(@transfer_manager).to receive(:download_file) {
        raise Aws::S3::Errors::NoSuchKey.new(
          Seahorse::Client::RequestContext.new, "Object key does not exist!"
        )
      }

      expect {
        subject.retrieve_file(remote_file_path: "nosuchfile.txt", local_dir_path: temp_dir)
      }.to raise_error(RemoteClient::RemoteClientError)
    end

    it "throws a remote client error when multi-part download error is encountered" do
      expect(@transfer_manager).to receive(:download_file) {
        raise Aws::S3::MultipartDownloadError.new("Your multi-part download failed, oh no!")
      }

      expect {
        subject.retrieve_file(remote_file_path: "file.txt", local_dir_path: temp_dir)
      }.to raise_error(RemoteClient::RemoteClientError)
    end
  end

  context "#retrieve_from_path" do
    it "puts the files (with their relative directory structure) into expected place" do
      allow(@bucket).to receive(:objects).and_return([
        FakeObject.new(key: "/parent/child/here/file1.txt"),
        FakeObject.new(key: "/parent/child/here/file2.txt")
      ].to_enum)
      expect(@transfer_manager).to receive(:download_directory).with(
        instance_of(String), bucket: "my-s3-bucket", s3_prefix: "parent/child/here"
      ) { |destination, kwargs|
        directories = File.join(*[destination, kwargs[:s3_prefix]].compact)
        FileUtils.mkdir_p(directories)
        ["file1.txt", "file2.txt"].each do |filename|
          FileUtils.touch(File.join(directories, filename))
        end
      }

      subject.retrieve_from_path(local_path: temp_dir, remote_path: "parent/child/here")
      expect(File.exist?("#{temp_dir}/here/file1.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/here/file2.txt")).to eq(true)
    end

    it "exits early when no files are found" do
      allow(@bucket).to receive(:objects).and_return([].to_enum)
      expect {
        subject.retrieve_from_path(local_path: temp_dir, remote_path: "no/such/path")
      }.to_not raise_error
    end

    it "throws a remote client error when download directory error occurs" do
      allow(@bucket).to receive(:objects).and_return([
        FakeObject.new(key: "/parent/child/here/file1.txt"),
        FakeObject.new(key: "/parent/child/here/file2.txt")
      ].to_enum)
      expect(@transfer_manager).to receive(:download_directory) {
        raise Aws::S3::DirectoryDownloadError.new(
          "There was an error downloading a directory, oh no!", [Exception.new]
        )
      }

      expect {
        subject.retrieve_from_path(local_path: temp_dir, remote_path: "parent/child/here")
      }.to raise_error(RemoteClient::RemoteClientError)
    end
  end

  context "#retrieve_all" do
    it "puts all the files (with their relative directory structure) into expected place" do
      expect(@transfer_manager).to receive(:download_directory).with(
        temp_dir, bucket: "my-s3-bucket"
      ) { |destination|
        directories = File.join(destination, "child")
        FileUtils.mkdir_p(directories)
        ["file1.txt", "file2.txt"].each do |filename|
          FileUtils.touch(File.join(directories, filename))
        end
        FileUtils.touch(File.join(destination, "file3.txt"))
      }

      subject.retrieve_all(local_path: temp_dir)
      expect(File.exist?("#{temp_dir}/child/file1.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/child/file2.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/file3.txt")).to eq(true)
    end

    it "throws a remote client error when download directory error occurs" do
      expect(@transfer_manager).to receive(:download_directory) {
        raise Aws::S3::DirectoryDownloadError.new(
          "There was an error downloading a directory, oh no!", [Exception.new]
        )
      }
      expect { subject.retrieve_all(local_path: temp_dir) }.to raise_error(RemoteClient::RemoteClientError)
    end
  end
end
