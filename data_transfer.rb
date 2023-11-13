require "logger"

LOGGER = Logger.new($stdout)

module DataTransfer
  module DataTransferUtils
    def do_transfer?(target_path)
      do_copy = true
      if File.exist? target_path
        LOGGER.debug "skipping copy because #{target_path} already exists"
        do_copy = false
      end
      do_copy
    end
  end

  class DataTransferBase
    include DataTransferUtils

    def transfer(target_dir)
      raise NotImplementedError
    end
  end

  class DirDataTransfer < DataTransferBase
    attr_reader :source_dir

    def initialize(source_dir)
      @source_dir = source_dir
    end

    def transfer(target_dir)
      file_paths = Dir[@source_dir + "/*"]
      LOGGER.debug("Files found in source directory: #{file_paths}")
      file_paths.each do |file_path|
        file_name = File.basename(file_path)
        target_file_path = File.join(target_dir, file_name)
        do_transfer = do_transfer? target_file_path
        if do_transfer
          FileUtils.cp_r(file_path, target_file_path)
        end
      end
    end
  end
end
