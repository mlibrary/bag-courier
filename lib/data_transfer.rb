require_relative "remote_client"

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
      RemoteClient::FileSystemRemoteClient.new(@source_dir)
        .retrieve_from_path(local_path: target_dir)
    end
  end
end
