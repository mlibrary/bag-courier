module DataTransfer
  class DataTransferBase
    def transfer(target_dir)
      raise NotImplementedError
    end
  end

  class RemoteClientDataTransfer < DataTransferBase
    def initialize(remote_client:, remote_path:)
      @remote_client = remote_client
      @remote_path = remote_path
    end

    def transfer(target_dir)
      @remote_client.retrieve_from_path(
        remote_path: @remote_path, local_path: target_dir
      )
    end
  end
end
