class FakeTransferManagerForPath
  def download_directory(destination, bucket:, **options)
    prefix = options[:s3_prefix]
    directories = File.join(*[destination, prefix].compact)
    FileUtils.mkdir_p(directories)

    ["file1.txt", "file2.txt"].each do |filename|
      FileUtils.touch(File.join(directories, filename))
    end
  end
end

class FakeTransferManagerForRoot
  def download_directory(destination, bucket:, **options)
    directories = File.join(destination, "child")
    FileUtils.mkdir_p(directories)

    ["file1.txt", "file2.txt"].each do |filename|
      FileUtils.touch(File.join(directories, filename))
    end
    FileUtils.touch(File.join(destination, "file3.txt"))
  end
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

  context "#remote_text" do
    it "returns the expected text" do
      expect(subject.remote_text).to eq('AWS S3 remote location in bucket "my-s3-bucket"')
    end
  end

  context "#send_file" do
    it "should call transfer manager with the correct arguments" do
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
  end

  context "#retrieve_from_path" do
    it "puts the files (with their relative directory structure) into expected place" do
      @transfer_manager = FakeTransferManagerForPath.new

      subject.retrieve_from_path(local_path: temp_dir, remote_path: "parent/child/here")
      expect(File.exist?("#{temp_dir}/here/file1.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/here/file2.txt")).to eq(true)
    end
  end

  context "#retrieve_all" do
    it "puts all the files (with their relative directory structure) into expected place" do
      @transfer_manager = FakeTransferManagerForRoot.new

      subject.retrieve_all(local_path: temp_dir)
      expect(File.exist?("#{temp_dir}/child/file1.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/child/file2.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/file3.txt")).to eq(true)
    end
  end
end

