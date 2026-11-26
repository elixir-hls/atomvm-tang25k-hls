defmodule FMBenchSignal do
  @moduledoc """
  FMBench's input, made on the host when FMBench compiles (floats, :math): a stereo FM broadcast as the
  RTL-SDR gives it, IQ bytes (I, Q, I, Q, ...; offset binary) at 960 kS/s. L a 1 kHz tone, R a 3 kHz one
  at half its level, the 19 kHz pilot at 10 %, L-R on 38 kHz, 75 kHz deviation, a little noise from a
  fixed generator: the same bytes on every build.
  """

  import Bitwise
  @fs 960_000.0

  def stereo(n) do
    {bytes, _} =
      Enum.map_reduce(0..(n - 1), {0.0, 12345}, fn k, {phi, seed} ->
        t = k / @fs
        l = :math.sin(2 * :math.pi() * 1000 * t)
        r = 0.5 * :math.sin(2 * :math.pi() * 3000 * t)
        wp = 2 * :math.pi() * 19_000 * t
        m = 0.9 * ((l + r) / 2 + (l - r) / 2 * :math.sin(2 * wp)) + 0.1 * :math.sin(wp)
        phi = phi + 2 * :math.pi() * 75_000 * m / @fs
        {ni, seed} = noise(seed)
        {nq, seed} = noise(seed)
        i = byte(100 * :math.cos(phi) + ni)
        q = byte(100 * :math.sin(phi) + nq)
        {[i, q], {phi, seed}}
      end)

    :erlang.list_to_binary(bytes)
  end

  @doc """
  FMBench's chain on the CPU (its defhls functions as Elixir) over `input` from reset, with the levels
  `blend` and `gain`: the frames as the CPU end gives them, their count, the pilot PLL's and the level's last
  states. Run on the host when FMBenchRef compiles.
  """
  def expected(input, blend, gain) do
    xs = :erlang.binary_to_list(input) |> FMBench.pairs() |> FMBench.channel() |> FMBench.discriminator() |> FMBench.mpx()
    {xm, pilot} = EHLS.run_cpu(&FMBench.pilot_pll/2, xs, {0, 0, 0, 0, 0, 0, 0, 0})
    {frames, level} = EHLS.run_cpu(&FMBench.level/2, FMBench.audio(xm, blend), 0)
    frames = for f <- frames, do: FMBench.volume(f, gain)
    bin = :erlang.list_to_binary(for f <- frames, do: <<f::little-32>>)
    %{bin: bin, n: length(frames), pilot: pilot, level: level}
  end

  @doc "n pseudo-random bytes"
  def noise_bytes(n) do
    {bytes, _} = Enum.map_reduce(1..n, 777, fn _, s -> s = lcg(s); {s >>> 16 &&& 0xFF, s} end)
    :erlang.list_to_binary(bytes)
  end

  defp lcg(s), do: s * 1_103_515_245 + 12345 &&& 0x7FFFFFFF
  # -2..2
  defp noise(s), do: (s = lcg(s); {rem(s >>> 16, 5) - 2, s})
  defp byte(v), do: min(255, max(0, round(v) + 128))
end

defmodule FMBench do
  @moduledoc """
  The FM radio's demodulator (atomvm-fm-radio: the IQ bytes to the audio frames, nothing of the USB
  host or I2S) between CPU ends, on fixed data, its output compared with the same functions on the CPU
  sample for sample (the expected outputs computed on the host when it compiles, FMBenchRef). A check of the HLS circuits on the board that needs no antenna and no listening:
  the same result on every run. One line per check, `FM BENCH OK` at the end.

  The checks, each from a start: a stereo FM signal (FMBenchSignal) at full stereo and full volume; mono
  and a lower volume; pseudo-random bytes at half the blend; the stereo signal again while another process
  reads the pilot PLL's and the level's states and writes the levels with the values they have (the output
  unchanged), and the states read at the end against the CPU's; 200 streams while the states are read without a
  pause (a hold anywhere in an element); the stream sent in two calls (the state
  goes on); a stop in the middle of a stream, a start and a stream sent at once (as from reset; the stopped call
  times out), and 40 times so, stopped at another point each time.

  The functions are the radio's; one change: the pilot PLL's window is 2^10 MPX samples (2^14 in the
  radio), so that the short input goes through several window ends.

  Build (in examples/; ELIXIR_HLS=<an elixir-hls checkout> for another one than ../elixir-hls):

      ../scripts/build_kernel.sh lib/fm_bench_coeffs.ex lib/fm_bench.ex && ../scripts/build_soc.sh
      ../scripts/build_atomvm.sh && ../scripts/flash.sh vm
      ../scripts/build_ex.sh fm_bench FMBench && ../scripts/run.sh fm_bench
  """
  use EHLS
  import Bitwise

  # 16384 IQ samples (17 ms): 4081 MPX samples (3 pilot windows), 772 audio frames; the expected outputs
  # in FMBenchRef
  @stereo FMBenchSignal.stereo(16_384)
  @noise FMBenchSignal.noise_bytes(32_768)
  # streams in the stress check
  @stress 200

  defhls sat16(v :: s32) :: s16 do
    if v > 32767, do: 32767, else: if(v < -32768, do: -32768, else: v)
  end

  defhls offset8(v :: s32) :: u8 do
    if v > 127, do: 255, else: if(v < -128, do: 0, else: v + 128)
  end

  defhls volume(frame :: u32, gain :: u9) :: u32 do
    g = if gain > 256, do: 256, else: gain
    l = signed(frame &&& 0xFFFF, 16) * g >>> 8
    r = signed(frame >>> 16, 16) * g >>> 8
    (l &&& 0xFFFF) ||| (r &&& 0xFFFF) <<< 16
  end

  defhls level(frame :: u32, peak :: u16) :: {u32, u16} do
    v = signed(frame &&& 0xFFFF, 16)
    a = if v < 0, do: -v, else: v
    decayed = peak - (peak >>> 12)
    {frame, if(a > decayed, do: a, else: decayed)}
  end

  defhls iq_pair(b :: u8, st :: {u8, u8}) :: {[u16], {u8, u8}} do
    {have_i, i} = st
    if have_i == 1, do: {[(i <<< 8 ||| b) ^^^ 0x8080], {0, 0}}, else: {[], {1, b}}
  end

  @chan FMBenchCoeffs.chan()

  defhls chan_tap(w :: tuple(u16, 31)) :: u16 do
    {ai, aq} =
      for k <- 0..15, reduce: {0, 0} do
        {ai, aq} ->
          a = elem(w, 30 - k)
          b = elem(w, k)
          c = Enum.at(@chan, k)
          {bi, bq} = if k == 15, do: {0, 0}, else: {signed(b >>> 8, 8), signed(b &&& 0xFF, 8)}
          {signed(ai + (signed(a >>> 8, 8) + bi) * c, 32), signed(aq + (signed(a &&& 0xFF, 8) + bq) * c, 32)}
      end

    yi = (ai + 32768) >>> 16
    yq = (aq + 32768) >>> 16
    (offset8(yi) <<< 8) ||| offset8(yq)
  end

  @atan [8192, 4836, 2555, 1297, 651, 326, 163, 81, 41, 20, 10, 5, 3, 1, 1, 0]

  defhls phase(iq :: u16) :: u16 do
    i = (iq >>> 8 &&& 0xFF) - 128
    q = (iq &&& 0xFF) - 128
    {x0, y0, z0} = if i < 0, do: {-(i <<< 9), -(q <<< 9), 0x8000}, else: {i <<< 9, q <<< 9, 0}

    {_x, _y, z} =
      for k <- 0..15, reduce: {x0, y0, z0} do
        {x, y, z} ->
          if y >= 0 do
            {signed(x + (y >>> k), 21), signed(y - (x >>> k), 21), unsigned(z + Enum.at(@atan, k), 16)}
          else
            {signed(x - (y >>> k), 21), signed(y + (x >>> k), 21), unsigned(z - Enum.at(@atan, k), 16)}
          end
      end

    z
  end

  defhls phase_step(ph :: u16, prev :: u16) :: {s16, u16} do
    {signed(ph - prev, 16), ph}
  end

  @fir1 FMBenchCoeffs.fir1()
  @fir2 FMBenchCoeffs.fir2()

  defhls mpx_tap(w :: tuple(s16, 32)) :: s18 do
    v = Enum.sum(for k <- 0..31, do: elem(w, 31 - k) * Enum.at(@fir1, k)) >>> 15
    if v > 131_071, do: 131_071, else: if(v < -131_072, do: -131_072, else: v)
  end

  @sin FMBenchCoeffs.sin()

  # the radio's pilot PLL, its window 2^10 samples
  defhls pilot_pll(x :: s18, st :: {u32, s32, s24, s24, u32, s32, s32, u32}) :: {{s18, s20}, {u32, s32, s24, s24, u32, s32, s32, u32}} do
    {theta, integ, i_lp, q_lp, win, si, sq, pilot} = st
    a = theta >>> 22
    s1 = Enum.at(@sin, a)
    c1 = Enum.at(@sin, a + 256)
    s2 = Enum.at(@sin, theta >>> 21)
    pd = x * c1
    m = (x * s2) >>> 14
    i2 = signed(i_lp + (((x * s1) >>> 15) - i_lp + 128 >>> 8), 24)
    q2 = signed(q_lp + ((pd >>> 15) - q_lp + 128 >>> 8), 24)
    integ1 = integ + (pd >>> 16)
    integ2 = if integ1 > 1_048_576, do: 1_048_576, else: if(integ1 < -1_048_576, do: -1_048_576, else: integ1)
    theta2 = unsigned(theta + 0x14444444 + (pd >>> 6) + integ2, 32)
    si2 = signed(si + i2, 32)
    sq2 = signed(sq + q2, 32)
    win2 = unsigned(win + 1, 22)

    {si3, sq3, pilot2} =
      if (win &&& 0x3FF) == 0x3FF do
        pi = sat16(si2 >>> 10)
        pq = sat16(sq2 >>> 10)
        {0, 0, (pi &&& 0xFFFF) ||| (pq &&& 0xFFFF) <<< 16}
      else
        {si2, sq2, pilot}
      end

    {{x, m}, {theta2, integ2, i2, q2, win2, si3, sq3, pilot2}}
  end

  defhls stereo_tap(w :: tuple({s18, s20}, 225)) :: {s22, s22} do
    {s, d} =
      for k <- 0..223, reduce: {0, 0} do
        {s, d} ->
          {x, m} = elem(w, 224 - k)
          c = Enum.at(@fir2, k)
          {signed(s + x * c, 44), signed(d + m * c, 46)}
      end

    {s >>> 17, d >>> 17}
  end

  defhls stereo_out(sd :: {s22, s22}, st :: {s22, s32, s32}, blend :: u9) :: {u32, {s22, s32, s32}} do
    {s, d} = sd
    {dc, yl, yr} = st
    dc2 = signed(dc + ((s - dc + 512) >>> 10), 22)
    sp = signed(s - dc2, 22)
    dg = (d * blend) >>> 8
    l = signed(sp + dg, 24)
    r = signed(sp - dg, 24)
    yl2 = yl + (((l <<< 8) - yl) * 87 >>> 8)
    yr2 = yr + (((r <<< 8) - yr) * 87 >>> 8)
    ol = sat16(yl2 >>> 8)
    orr = sat16(yr2 >>> 8)
    {(ol &&& 0xFFFF) ||| (orr &&& 0xFFFF) <<< 16, {dc2, yl2, yr2}}
  end

  # the chain in parts, as the radio's; on the CPU each takes a list and gives a list
  defhls pairs(b :: stream(u8)) :: stream(u16) do
    b |> transform({0, 0}, &iq_pair/2)
  end

  defhls channel(iq :: stream(u16)) :: stream(u16) do
    iq |> chunk_every(31, 1, :discard) |> map(&chan_tap/1)
  end

  defhls discriminator(iq :: stream(u16)) :: stream(s16) do
    iq |> map(&phase/1) |> transform(0, &phase_step/2)
  end

  defhls mpx(d :: stream(s16)) :: stream(s18) do
    d |> chunk_every(32, 4, :discard) |> map(&mpx_tap/1)
  end

  defhls audio(xm :: stream({s18, s20}), blend :: u9) :: stream(u32) do
    xm |> chunk_every(225, 5, :discard) |> map(&stereo_tap/1) |> transform({0, 0, 0}, &stereo_out(&1, &2, blend))
  end

  definstance gain_hw(g :: u9), initial: 256 do
    g
  end

  definstance blend_hw(b :: u9), initial: 256 do
    b
  end

  # the radio's demodulator, the IQ bytes in from the CPU, the frames out to it
  definstance bench(iq) do
    iq
    |> pairs()
    |> channel()
    |> discriminator()
    |> mpx()
    |> transform({0, 0, 0, 0, 0, 0, 0, 0}, &pilot_pll/2, name: :pilot)
    |> audio(blend_hw(:value))
    |> transform(0, &level/2, name: :level)
    |> map(&volume(&1, gain_hw(:value)))
  end

  # -- the checks --

  def start do
    parent = self()
    :erlang.spawn_opt(fn -> checks(); send(parent, :done) end, [{:atomvm_heap_growth, :fibonacci}])

    receive do
      :done -> :ok
    end
  end

  defp checks do
    :timer.sleep(50)
    stereo = FMBenchRef.stereo()
    IO.puts("expected (computed on the host): #{stereo.n} frames from #{byte_size(@stereo)} bytes; " <>
              "the pilot #{pilot_level(stereo.pilot)}")

    run("stereo, full volume", @stereo, stereo, 256, 256)
    check("... the pilot PLL's state read at the end is the CPU's", same_pilot(bench(:state, :pilot), stereo.pilot))
    check("... the level's state too", bench(:state, :level) == stereo.level)

    run("mono, volume 64", @stereo, FMBenchRef.mono(), 0, 64)
    run("pseudo-random bytes, blend 128", @noise, FMBenchRef.noise(), 128, 256)

    # the states read and the levels written (with the values they have) all the while
    restart(256, 256)
    me = self()
    reader = spawn(fn -> busy_reader(me, 0) end)
    out = call(@stereo, stereo)
    send(reader, :stop)
    reads = receive do
      {:reads, n} -> n
    end
    check("stereo while the states are read and the levels written (#{reads} times)", out == stereo.bin)
    check("... the pilot PLL's state at the end", same_pilot(bench(:state, :pilot), stereo.pilot))

    # many streams while the states are read without a pause: a hold of the pilot PLL's stage falls anywhere in
    # its elements (the FM radio's stream once stopped so, a kernel and its adapter waiting for each other)
    reader = spawn(fn -> busy_reader(me, 0) end)
    {good, why} = stress(stereo, @stress, 0)
    send(reader, :stop)
    reads = receive do
      {:reads, n} -> n
    end
    check("#{@stress} streams while the states are read (#{reads} times): #{good} right#{why}", good == @stress)

    # in two calls: the stage states go on
    restart(256, 256)
    {split, n1} = FMBenchRef.split()
    {first, second} = :erlang.split_binary(@stereo, split)
    a = bench(first, out: n1, timeout: 5000)
    b = bench(second, out: stereo.n - n1, timeout: 5000)
    check("stereo in two calls (#{n1} + #{stereo.n - n1} frames)", a <> b == stereo.bin)

    # a stop in the middle, a start at once: the next stream as from reset
    restart(256, 256)
    caller = spawn(fn -> send(me, {:stopped_call, catch_error(fn -> bench(@stereo, out: stereo.n, timeout: 1000) end)}) end)
    :timer.sleep(3)
    bench(:stop)
    bench(:start)
    # sent at once, while the stages may still finish what they had begun: as from reset
    run("stereo sent right after the stop and start", @stereo, stereo, 256, 256, false)
    stopped = receive do
      {:stopped_call, r} -> r
    after
      3000 -> :no_answer
    end
    _ = caller
    # f(:stop) cancels what is in flight, no message follows: the call waiting for it times out
    check("... the call stopped in the middle ends (#{if is_binary(stopped), do: "it had finished", else: inspect(stopped)})",
          stopped == :timeout or is_binary(stopped))

    # stopped anywhere in a stream (0 .. 19 ms of its 20), started and a stream sent at once, 40 times
    {good, why} = stop_start(stereo, 0)
    check("40 streams stopped anywhere, each followed at once by a whole one: #{good} right#{why}", good == 40)

    IO.puts("FM BENCH #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp stop_start(_exp, 40), do: {40, ""}

  defp stop_start(exp, i) do
    restart(256, 256)
    :ok = bench(:request, :out, byte_size(exp.bin))
    :ok = bench(:send, :iq, @stereo)
    :timer.sleep(rem(i * 7, 20))
    bench(:stop)
    bench(:start)
    out = call(@stereo, exp)
    # what the stopped stream's request may have left: no message after a stop, but drop any
    flush()

    cond do
      out == exp.bin -> stop_start(exp, i + 1)
      is_binary(out) -> {i, ", then #{i + 1} (after #{rem(i * 7, 20)} ms)#{first_difference(out, exp.bin)}"}
      true -> {i, ", then #{i + 1} (after #{rem(i * 7, 20)} ms): #{inspect(out)}"}
    end
  end

  defp flush do
    receive do
      {:bench, _, _} -> flush()
    after
      0 -> :ok
    end
  end

  defp stress(_exp, n, n), do: {n, ""}

  defp stress(exp, n, i) do
    restart(256, 256)

    case call(@stereo, exp) do
      out when out == exp.bin -> stress(exp, n, i + 1)
      out when is_binary(out) -> {i, ", then #{i + 1}#{first_difference(out, exp.bin)}"}
      e -> {i, ", then #{i + 1}: #{inspect(e)}"}
    end
  end

  # one stream from a start, the levels set before, the output against the CPU's
  defp run(label, input, exp, blend, gain, restart? \\ true) do
    if restart?, do: restart(blend, gain)
    t0 = :erlang.monotonic_time(:millisecond)
    out = call(input, exp)
    t1 = :erlang.monotonic_time(:millisecond)
    check("#{label}: #{exp.n} frames, FPGA #{t1 - t0} ms#{first_difference(out, exp.bin)}", out == exp.bin)
  end

  defp call(input, exp) do
    case catch_error(fn -> bench(input, out: exp.n, timeout: 5000) end) do
      out when is_binary(out) -> out
      e -> e
    end
  end

  defp restart(blend, gain) do
    bench(:stop)
    blend_hw(blend)
    gain_hw(gain)
    bench(:start)
  end

  # the states as their fields' bits (the CPU's integers may be negative)
  @pilot_bits [32, 32, 24, 24, 22, 32, 32, 32]
  defp same_pilot(a, b) when is_tuple(a) and is_tuple(b), do: bits(a) == bits(b)
  defp same_pilot(_, _), do: false
  defp bits(t), do: for({v, n} <- :lists.zip(:erlang.tuple_to_list(t), @pilot_bits), do: v &&& (1 <<< n) - 1)

  defp pilot_level({_, _, _, _, _, _, _, p}), do: "in-phase #{signed(p &&& 0xFFFF, 16)}, quadrature #{signed(p >>> 16 &&& 0xFFFF, 16)}"

  defp first_difference(out, exp) when is_binary(out) and byte_size(out) == byte_size(exp) do
    if out == exp, do: "", else: " (frame #{differs_at(out, exp, 0)} differs)"
  end

  defp first_difference(out, exp) when is_binary(out), do: " (#{byte_size(out)} bytes, not #{byte_size(exp)})"
  defp first_difference(e, _), do: " (#{inspect(e)})"

  defp differs_at(<<a::32, ra::binary>>, <<a::32, rb::binary>>, i), do: differs_at(ra, rb, i + 1)
  defp differs_at(_, _, i), do: i

  defp busy_reader(parent, n) do
    receive do
      :stop -> send(parent, {:reads, n})
    after
      0 ->
        _ = bench(:state, :pilot)
        _ = bench(:state, :level)
        blend_hw(256)
        gain_hw(256)
        busy_reader(parent, n + 1)
    end
  end

  defp catch_error(fun) do
    try do
      fun.()
    catch
      :error, reason -> reason
    end
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
