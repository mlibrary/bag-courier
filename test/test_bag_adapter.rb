require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/bag_adapter"

class BagAdapterTest < Minitest::Test
  def setup
    @test_dir_path = File.join(__dir__, "bag_test_dir")
    @data_dir_path = File.join(@test_dir_path, "data")
    @test_bag_info_data = {"Some-Custom-Key": "Some Value"}
    @test_tag_file_name = "some-tag-file.txt"
    @test_tag_file_text = "TAG FILE TEXT GOES HERE"

    # Reset test directory
    FileUtils.rm_r(@test_dir_path) if File.exist?(@test_dir_path)
    Dir.mkdir @test_dir_path
  end

  def add_data_file
    File.write(
      File.join(@data_dir_path, "something.txt"),
      "Something to be preserved"
    )
  end

  def test_bag_dir
    assert_equal(
      BagAdapter::BagAdapter.new(@test_dir_path).bag_dir,
      @test_dir_path
    )
  end

  def test_data_dir
    assert_equal(
      BagAdapter::BagAdapter.new(@test_dir_path).data_dir,
      @data_dir_path
    )
  end

  def test_add_bag_info
    expected_text = <<~TEXT
      Bag-Software-Agent: BagIt Ruby Gem (https://github.com/tipr/bagit)
      Bagging-Date: 2023-12-22
      Payload-Oxum: 25.1
      Some-Custom-Key: Some Value
    TEXT

    Date.stub :today, Date.new(2023, 12, 22) do
      bag = BagAdapter::BagAdapter.new(@test_dir_path)
      add_data_file
      bag.add_bag_info(@test_bag_info_data)
    end

    file_text = File.read(File.join(@test_dir_path, "bag-info.txt"))
    assert_equal expected_text, file_text
  end

  def test_add_tag_file
    bag = BagAdapter::BagAdapter.new(@test_dir_path)
    bag.add_tag_file!(tag_file_text: @test_tag_file_text, file_name: @test_tag_file_name)

    expected_file_path = File.join(@test_dir_path, @test_tag_file_name)
    assert_equal [expected_file_path], bag.additional_tag_files
    assert File.exist?(expected_file_path)
    if File.exist?(expected_file_path)
      assert_equal @test_tag_file_text, File.read(expected_file_path)
    end
  end

  def test_add_manifests
    bag = BagAdapter::BagAdapter.new(@test_dir_path)
    add_data_file
    bag.add_tag_file!(tag_file_text: @test_tag_file_text, file_name: @test_tag_file_name)
    bag.add_manifests

    assert File.exist?(File.join(@test_dir_path, "manifest-md5.txt"))

    expected_tagmanifest_path = File.join(@test_dir_path, "tagmanifest-md5.txt")
    assert File.exist?(expected_tagmanifest_path)
    if File.exist?(expected_tagmanifest_path)
      file_text = File.read(expected_tagmanifest_path)
      assert file_text.include?(@test_tag_file_name)
      assert file_text.include?("bag-info.txt")
    end

    assert !File.exist?(File.join(@test_dir_path, "tagmanifest-sha1.txt"))
  end
end
