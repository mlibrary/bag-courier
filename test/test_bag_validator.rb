require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/bag_adapter"
require_relative "../lib/bag_validator"

describe InnerBagValidator do
  describe "#validate_inner_bag without hidden files and no detect hidden" do
    # Set up the test environment
    before do
      @test_dir_path = File.join(__dir__, "test_bag_val_dir")

      if Dir.exist?(@test_dir_path)
       # Delete the folder
       FileUtils.rm_rf(@test_dir_path)
      end

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
      @detect_hidden_no = false
      @innerbag = BagAdapter::BagAdapter.new(
        target_dir: @data_dir_path, detect_hidden: @detect_hidden_no)
      @innerbag.add_manifests

      @bag = BagAdapter::BagAdapter.new(
        target_dir: @test_dir_path, detect_hidden: @detect_hidden_no
      )
      @test_data_dir = @bag.data_dir
      @bag.add_manifests
    end

     it "returns true if the bag is valid" do
      result = InnerBagValidator.new(@inner_bag_path, @detect_hidden_no).validate(@test_data_dir)
      assert(result)
    end

    it "returns error if the bag is not valid" do
      # Modify the bag-info.txt file to make it invalid
      File.open(File.join(@data_dir_path, "bag-info.txt"), "a") do |file|
        file.puts "Invalid line"
      end
      assert_raises(BagValidationError) do
        InnerBagValidator.new(@inner_bag_path, @detect_hidden_no).validate(@test_data_dir)
      end
    end

    it "returns error if the bag path is not valid" do
      @random_path = @data_dir_path + "/test"
      assert_raises(BagValidationError) do
        InnerBagValidator.new(@inner_bag_path, @detect_hidden_no).validate(@random_path)
      end
    end
  end

  describe "#validate_inner_bag without hidden files and detect hidden" do
    # Set up the test environment
    before do
      @test_dir_path = File.join(__dir__, "test_bag_val_dir")

      if Dir.exist?(@test_dir_path)
       # Delete the folder
       FileUtils.rm_rf(@test_dir_path)
      end

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
      @detect_hidden_yes = true
      @innerbag = BagAdapter::BagAdapter.new(
        target_dir: @data_dir_path, detect_hidden: @detect_hidden_yes
      )
      @innerbag.add_manifests

      @bag = BagAdapter::BagAdapter.new(
        target_dir: @test_dir_path, detect_hidden: @detect_hidden_yes)
      @test_data_dir = @bag.data_dir
      @bag.add_manifests
    end

    it "returns true if the bag is valid" do
      result = InnerBagValidator.new(@inner_bag_path, @detect_hidden_yes).validate(@test_data_dir)
      assert(result)
    end

    it "returns error if the bag is not valid" do
      # Modify the bag-info.txt file to make it invalid
      File.open(File.join(@data_dir_path, "bag-info.txt"), "a") do |file|
        file.puts "Invalid line"
      end
      assert_raises(BagValidationError) do
        InnerBagValidator.new(@inner_bag_path, @detect_hidden_yes).validate(@test_data_dir)
      end
    end

    it "returns error if the bag path is not valid" do
      @random_path = @data_dir_path + "/test"
      assert_raises(BagValidationError) do
        InnerBagValidator.new(@inner_bag_path, @detect_hidden_yes).validate(@random_path)
      end
    end
  end

  describe "#validate_inner_bag with hidden files and detect hidden" do
    # Set up the test environment
    before do

      @test_dir_path = File.join(__dir__, "test_bag_val_dir")

      if Dir.exist?(@test_dir_path)
       # Delete the folder
       FileUtils.rm_rf(@test_dir_path)
      end

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

      @detect_hidden_yes = true
      @hidden_file_base_path = @data_dir_path + "/data/objects/Before_I_Forget"
      @hidden_files = [
        File.join(@hidden_file_base_path, "._BeforeIForget_Linux.zip"),
        File.join(@hidden_file_base_path, "._BeforeIForget_Mac.app.zip"),
        File.join(@hidden_file_base_path, "._BeforeIForget_PC.zip"),
        File.join(@hidden_file_base_path, "._Store_Page.pdf"),
        File.join(@hidden_file_base_path, "testStore_Page.txt")
      ]
      @txt_file_content = "some text inside zip"
      FileUtils.mkdir_p(@hidden_file_base_path)

      @hidden_files.select { |file| file.end_with?(".zip") }.each do |zip|
        File.open(zip, "wb"){ }
      end
      File.open(@hidden_files[3], "wb") do |file|
        file.write(@txt_file_content)
      end

      File.open(@hidden_files[4], "wb") do |file|
        file.write(@txt_file_content)
      end

      @innerbag = BagAdapter::BagAdapter.new(
        target_dir: @data_dir_path, detect_hidden: @detect_hidden_yes
      )
      @innerbag.add_manifests

      @bag = BagAdapter::BagAdapter.new(
        target_dir: @test_dir_path, detect_hidden: @detect_hidden_yes
      )
      @test_data_dir = @bag.data_dir
      @bag.add_manifests
    end

    it "returns true if the bag is valid with hidden files" do
      result = InnerBagValidator.new(@inner_bag_path, @detect_hidden_yes).validate(@test_data_dir)
      assert(result)
    end

    it "returns error if the bag is not valid with hidden files" do
      # Modify the bag-info.txt file to make it invalid
      File.open(File.join(@data_dir_path, "bag-info.txt"), "a") do |file|
        file.puts "Invalid line"
      end
      assert_raises(BagValidationError) do
        InnerBagValidator.new(@inner_bag_path, @detect_hidden_yes).validate(@test_data_dir)
      end
    end

    it "returns error if the bag path is not valid with hidden files" do
      @random_path = @data_dir_path + "/test"
      assert_raises(BagValidationError) do
        InnerBagValidator.new(@inner_bag_path, @detect_hidden_yes).validate(@random_path)
      end
    end
  end

  describe "#validate_inner_bag with hidden files and no detect hidden" do
    # Set up the test environment
    before do

      @test_dir_path = File.join(__dir__, "test_bag_val_dir")

      if Dir.exist?(@test_dir_path)
       # Delete the folder
       FileUtils.rm_rf(@test_dir_path)
      end

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

      @detect_hidden_no = false
      @hidden_file_base_path = @data_dir_path + "/data/objects/Before_I_Forget"
      @hidden_files = [
        File.join(@hidden_file_base_path, "._BeforeIForget_Linux.zip"),
        File.join(@hidden_file_base_path, "._BeforeIForget_Mac.app.zip"),
        File.join(@hidden_file_base_path, "._BeforeIForget_PC.zip"),
        File.join(@hidden_file_base_path, "._Store_Page.pdf"),
        File.join(@hidden_file_base_path, "testStore_Page.txt")
      ]
      @txt_file_content = "some text inside zip"
      FileUtils.mkdir_p(@hidden_file_base_path)

      @hidden_files.select { |file| file.end_with?(".zip") }.each do |zip|
        File.open(zip, "wb"){ }
      end
      File.open(@hidden_files[3], "wb") do |file|
        file.write(@txt_file_content)
      end

      File.open(@hidden_files[4], "wb") do |file|
        file.write(@txt_file_content)
      end

      @innerbag = BagAdapter::BagAdapter.new(
        target_dir: @data_dir_path, detect_hidden: @detect_hidden_no
      )
      @innerbag.add_manifests

      @bag = BagAdapter::BagAdapter.new(
        target_dir: @test_dir_path, detect_hidden: @detect_hidden_no
      )
      @test_data_dir = @bag.data_dir
      @bag.add_manifests
    end

    it "returns true if the bag is valid with hidden files" do
      result = InnerBagValidator.new(@inner_bag_path, @detect_hidden_no).validate(@test_data_dir)
      assert(result)
    end

    it "returns error if the bag is not valid with hidden files" do
      # Modify the bag-info.txt file to make it invalid
      File.open(File.join(@data_dir_path, "bag-info.txt"), "a") do |file|
        file.puts "Invalid line"
      end
      assert_raises(BagValidationError) do
        InnerBagValidator.new(@inner_bag_path, @detect_hidden_no).validate(@test_data_dir)
      end
    end

    it "returns error if the bag path is not valid with hidden files" do
      @random_path = @data_dir_path + "/test"
      assert_raises(BagValidationError) do
        InnerBagValidator.new(@inner_bag_path, @detect_hidden_no).validate(@random_path)
      end
    end
  end
end
