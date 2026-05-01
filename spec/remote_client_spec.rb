class FakeTransferManager
  def download_directory(destination, bucket:, **options)
    prefix = options[:s3_prefix]
    directories = File.join([destination, prefix, "another_child"].compact)
    FileUtils.mkdir_p(directories)

    ["file1.txt", "file2.txt"].each do |filename|
      FileUtils.touch(File.join(directories, filename))
    end
  end
end
describe RemoteClient::AwsS3RemoteClient do
  include_context "uses temp dir"
  before(:each) do
    @bucket = instance_double(Aws::S3::Bucket, name: "my-s3-bucket")
    @transfer_manager = FakeTransferManager.new
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
  end
  context "retrieve_file" do
  end
  context "retrieve_from_path" do
    it "puts the files (with their relative directory structure) into expected place" do
      subject.retrieve_from_path(local_path: temp_dir, remote_path: "parent/child/here")
      expect(File.exist?("#{temp_dir}/another_child/file1.txt")).to eq(true)
      expect(File.exist?("#{temp_dir}/another_child/file2.txt")).to eq(true)
    end
  end
end
