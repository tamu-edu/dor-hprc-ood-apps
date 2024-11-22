require 'open3'

class Command
  def to_s
    "gpuavail -n"
  end

  # assign a variable name to each column of the command output
  AppProcess = Struct.new(:name, :gpu_type, :gpu_count, :gpu_avail, :cpu_avail, :mem_avail)

  # Parse a string output from the `gpuavail -n` command and return an array of
  # AppProcess objects, one per line
  def parse(output)
    lines = output.strip.split("\n")
    lines.map do |line|
      AppProcess.new(*(line.split(" ", 6)))
    end
  end

  # Execute the command, and parse the output, returning and array of
  # GPU availability and nil for the error string.
  #
  # returns [Array<Array<output>, String] i.e.[output, error]
  def exec
    output, error = [], nil

    stdout_str, stderr_str, status = Open3.capture3(to_s)
    if status.success?
      output = parse(stdout_str)
    else
      error = "Command '#{to_s}' exited with error: #{stderr_str}"
    end

    [output, error]
  end
end
