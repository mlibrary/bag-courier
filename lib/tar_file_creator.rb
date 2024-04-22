require "tty-command"

module TarFileCreator
  class TarFileCreatorError < StandardError
  end

  class TarFileCreator
    def initialize(command)
      @command = command
    end

    def self.setup
      new(TTY::Command.new)
    end

    def create_error_message(error)
      "#{self.class} failed: #{error}"
    end
    private :create_error_message

    def run_command(...)
      @command.run(...)
    rescue TTY::Command::ExitError => e
      raise TarFileCreatorError, create_error_message(e)
    end
    private :run_command

    def create(src_dir_path:, dest_file_path:, verbose: false)
      src_parent = File.dirname(src_dir_path)
      src_dir = File.basename(src_dir_path)
      flags = "-cf#{verbose ? "v" : ""}"
      run_command("tar", flags, dest_file_path, "--directory=#{src_parent}", src_dir)
    end

    def open(src_file_path:, dest_dir_path:)
      run_command("tar", "-xf", src_file_path, "-C", dest_dir_path)
    end
  end
end
