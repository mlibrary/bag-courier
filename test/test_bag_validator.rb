require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/bag_adapter"
require_relative "../lib/bag_validator"

describe InnerBagValidator do
  describe "#validate_inner_bag" do
    # Set up the test environment
    before do
      @test_dir_path = File.join(__dir__, "test_bag_val_dir")
      @inner_bag_path = "inner_test_bag"
      @data_dir_path = File.join(@test_dir_path, "data", @inner_bag_path)
      FileUtils.rm_r(@test_dir_path) if File.exist?(@test_dir_path)
      Dir.mkdir(@test_dir_path)
      FileUtils.mkdir_p(@data_dir_path)

      @something_txt_path = File.join(@data_dir_path, "data", "something.txt")
      FileUtils.mkdir_p(File.dirname(@something_txt_path))
      File.open(@something_txt_path, "w") do |file|
        file.puts "Some sample text for testing inner bag"
      end
      @detect_hidden = true
      @innerbag = BagAdapter::BagAdapter.new(
        target_dir: @data_dir_path, detect_hidden: @detect_hidden)
      @innerbag.add_manifests

      @bag = BagAdapter::BagAdapter.new(
        target_dir: @test_dir_path, detect_hidden: @detect_hidden
      )
      @test_data_dir = @bag.data_dir
      @bag.add_manifests
    end

    it "returns true if the bag is valid" do
      result = InnerBagValidator.new(inner_bag_name: @inner_bag_path, detect_hidden: @detect_hidden)
        .validate(@test_data_dir)
      assert(result)
    end

    it "returns error if the bag is not valid" do
      # Modify the bag-info.txt file to make it invalid
      File.open(File.join(@data_dir_path, "bag-info.txt"), "a") do |file|
        file.puts "Invalid line"
      end

      error = assert_raises(BagValidationError) do
        InnerBagValidator.new(inner_bag_name: @inner_bag_path, detect_hidden: @detect_hidden)
          .validate(@test_data_dir)
      end
      assert error.message.start_with?('Inner bag is not valid:')
    end

    it "returns error if the bag path is not valid" do
      @random_path = @data_dir_path + "/test"
      assert_raises(BagValidationError) do
        InnerBagValidator.new(inner_bag_name: @inner_bag_path, detect_hidden: @detect_hidden)
          .validate(@random_path)
      end
    end
  end
end
