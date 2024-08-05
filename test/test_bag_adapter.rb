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

    @regular_data_file_name = "something.txt"
    @hidden_data_file_name = ".hidden"

    # Reset test directory
    FileUtils.rm_r(@test_dir_path) if File.exist?(@test_dir_path)
    Dir.mkdir @test_dir_path
  end

  def add_data_files
    File.write(
      File.join(@data_dir_path, @regular_data_file_name),
      "Something to be preserved"
    )
    File.write(File.join(@data_dir_path, @hidden_data_file_name), "")
  end

  def test_bag_dir
    assert_equal(
      BagAdapter::BagAdapter.new(target_dir: @test_dir_path).bag_dir,
      @test_dir_path
    )
  end

  def test_data_dir
    assert_equal(
      BagAdapter::BagAdapter.new(target_dir: @test_dir_path).data_dir,
      @data_dir_path
    )
  end

  def test_add_bag_info
    expected_text = <<~TEXT
      Bag-Software-Agent: BagIt Ruby Gem (https://github.com/tipr/bagit)
      Bagging-Date: 2023-12-22
      Payload-Oxum: 25.2
      Some-Custom-Key: Some Value
    TEXT

    Date.stub :today, Date.new(2023, 12, 22) do
      bag = BagAdapter::BagAdapter.new(target_dir: @test_dir_path)
      add_data_files
      bag.add_bag_info(@test_bag_info_data)
    end

    file_text = File.read(File.join(@test_dir_path, "bag-info.txt"))
    assert_equal expected_text, file_text
  end

  def test_add_tag_file
    bag = BagAdapter::BagAdapter.new(target_dir: @test_dir_path)
    bag.add_tag_file!(tag_file_text: @test_tag_file_text, file_name: @test_tag_file_name)

    expected_file_path = File.join(@test_dir_path, @test_tag_file_name)
    assert_equal [expected_file_path], bag.additional_tag_files
    assert File.exist?(expected_file_path)
    if File.exist?(expected_file_path)
      assert_equal @test_tag_file_text, File.read(expected_file_path)
    end
  end

  def test_add_manifests
    bag = BagAdapter::BagAdapter.new(target_dir: @test_dir_path)
    add_data_files
    bag.add_tag_file!(tag_file_text: @test_tag_file_text, file_name: @test_tag_file_name)
    bag.add_manifests

    expected_manifest_file = File.join(@test_dir_path, "manifest-md5.txt")
    assert File.exist?(expected_manifest_file)
    if File.exist?(expected_manifest_file)
      file_text = File.read(expected_manifest_file)
      assert file_text.include?(@regular_data_file_name)
      assert file_text.include?(@hidden_data_file_name)
    end

    expected_tagmanifest_path = File.join(@test_dir_path, "tagmanifest-md5.txt")
    assert File.exist?(expected_tagmanifest_path)
    if File.exist?(expected_tagmanifest_path)
      file_text = File.read(expected_tagmanifest_path)
      assert file_text.include?(@test_tag_file_name)
      assert file_text.include?("bag-info.txt")
    end

    assert !File.exist?(File.join(@test_dir_path, "tagmanifest-sha1.txt"))
  end

  def test_add_manifests_when_detect_hidden_false
    bag = BagAdapter::BagAdapter.new(target_dir: @test_dir_path, detect_hidden: false)
    add_data_files
    bag.add_manifests

    expected_manifest_file = File.join(@test_dir_path, "manifest-md5.txt")
    assert File.exist?(expected_manifest_file)
    if File.exist?(expected_manifest_file)
      file_text = File.read(expected_manifest_file)
      assert file_text.include?(@regular_data_file_name)
      refute file_text.include?(@hidden_data_file_name)
    end
  end
end
