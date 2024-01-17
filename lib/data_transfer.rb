require "logger"

require_relative "remote"

LOGGER = Logger.new($stdout)

module DataTransfer
  class DataTransferBase
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
      Remote::FileSystemRemote.new(@source_dir).retrieve_dir(local_dir_path: target_dir)
    end
  end
end
