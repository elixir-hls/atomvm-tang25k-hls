defmodule FMBenchRef do
  @moduledoc "FMBench's expected results, computed on the host at compile time (FMBenchSignal.expected/3)."
  @stereo_in FMBenchSignal.stereo(16_384)
  @stereo FMBenchSignal.expected(@stereo_in, 256, 256)
  @mono FMBenchSignal.expected(@stereo_in, 0, 64)
  @noise FMBenchSignal.expected(FMBenchSignal.noise_bytes(32_768), 128, 256)
  # the stream in two calls: the frames of its first part
  @split 9_999
  @first FMBenchSignal.expected(binary_part(@stereo_in, 0, @split), 256, 256).n

  def stereo, do: @stereo
  def mono, do: @mono
  def noise, do: @noise
  def split, do: {@split, @first}
end
