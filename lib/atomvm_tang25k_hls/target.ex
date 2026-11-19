defmodule AtomVMTang25KHLS.Target do
  @moduledoc """
  The Sipeed Tang Primer 25K as elixir-hls' Mix tasks see it (`EHLS.Target`): `mix ehls.build`, `mix ehls.run`,
  `mix ehls.flash`, `mix ehls.console`, `mix ehls.doctor` in an application that has this package as a dependency.
  Each step calls this repository's scripts (scripts/), as they are run by hand.

  The steps of a build:

  | step | script | runs again when |
  |---|---|---|
  | `kernels` | build_kernel.sh (the files of lib/, when one has `use EHLS`) | lib/ or the packages' Elixir changed |
  | `soc` | build_soc.sh (Gowin) | the circuits' files (build/hw, not the simulations), the gateware or the options changed |
  | `atomvm` | build_atomvm.sh | the SoC's CSR map or the NIFs' C changed |
  | `pack` | build_ex.sh (the start module) | lib/ or the generated Erlang changed |

  The application's options, in `config :elixir_hls`: `gowin: [place: n, route: n]` (GW_PLACE / GW_ROUTE),
  `blocks: [:atomvm_tang25k_i2s, ...]` (the block packages; default: every dependency that depends on elixir-hls,
  the target and its base left out). An `hls.env` in the application is still read by the scripts, after these.

  The machine's settings (`EHLS.Machine`): `GOWIN_HOME` (found as `~/Gowin_*` or from `gw_sh` on `PATH`),
  `UART_PORT` (found in /dev/serial/by-id: the FT2232's second interface; else the scripts' /dev/ttyUSB1),
  `ATOMVM_TANG25K` (the base; found as the dependency once it is set up), `ZEPHYR_WORKSPACE` (found as
  `~/zephyrproject`).
  """
  @behaviour EHLS.Target

  @me Path.expand("../..", __DIR__)
  @bitstream "build/soc/gateware/sipeed_tang_primer_25k.fs"
  @vm "build/app_atomvm/zephyr/AtomVM.bin"
  @not_ours ~w(elixir_hls atomvm_tang25k atomvm_tang25k_hls)a

  @impl true
  def name, do: :tang25k

  @impl true
  def settings do
    [
      %{key: :gowin_home, env: "GOWIN_HOME", doc: "the Gowin IDE's directory (IDE/bin/gw_sh in it)", find: &find_gowin/0},
      %{key: :uart_port, env: "UART_PORT", doc: "the board's UART (the FT2232's second interface)", find: &find_port/0},
      %{key: :atomvm_tang25k, env: "ATOMVM_TANG25K", doc: "atomvm-tang25k, set up (its README)", find: &find_base/0},
      %{key: :zephyr_workspace, env: "ZEPHYR_WORKSPACE", doc: "the Zephyr workspace", find: &find_zephyr/0}
    ]
  end

  @impl true
  def steps(project) do
    ehls = EHLS.Project.dep_path(:elixir_hls)
    base = base(project)
    pkgs = Enum.map(blocks(project), &EHLS.Project.dep_path/1)
    files = kernel_files(project)
    junk = [~r{/sim_[^/]*$}, ~r{elixirc\.log$}, ~r{__pycache__}, ~r{\.pyc$}]

    [
      %{
        name: :kernels,
        doc: "the circuits, checked in simulation (build_kernel.sh)",
        inputs:
          ["lib/**/*.ex", "mix.lock", "#{ehls}/lib/**/*", "#{ehls}/priv/**/*", "#{@me}/scripts/build_kernel.sh"] ++
            for(p <- pkgs, do: "#{p}/lib/**/*.ex"),
        exclude: junk,
        values: files,
        outputs: if(files == [], do: [], else: ["build/hw/kernels.json"]),
        needs: if(files == [], do: [], else: [:circt_bin]),
        run: fn -> if files != [], do: script(project, "build_kernel.sh", files) end
      },
      %{
        name: :soc,
        doc: "the SoC with the circuits (build_soc.sh, Gowin)",
        inputs:
          ["build/hw/**/*", "#{@me}/gateware/**/*", "#{@me}/board_gpio.json", "#{@me}/scripts/build_soc.sh",
           "#{ehls}/priv/**/*", "#{base}/gateware/**/*"] ++ for(p <- pkgs, do: "#{p}/gateware/**/*"),
        exclude: junk,
        values: {project.config[:gowin], blocks(project)},
        outputs: ["build/soc/csr.json", @bitstream],
        needs: [:gowin_home],
        run: fn -> script(project, "build_soc.sh", []) end
      },
      %{
        name: :atomvm,
        doc: "AtomVM for that SoC, with the NIFs (build_atomvm.sh)",
        inputs:
          ["build/soc/csr.json", "build/gen/*.c", "#{ehls}/priv/backend/atomvm/src/**/*",
           "#{base}/apps/atomvm/**/*", "#{@me}/scripts/build_atomvm.sh"] ++ for(p <- pkgs, do: "#{p}/src/**/*"),
        exclude: junk,
        outputs: [@vm],
        run: fn -> script(project, "build_atomvm.sh", []) end
      },
      %{
        name: :pack,
        doc: "the application's pack, starting at #{inspect(project.start)}.start/0 (build_ex.sh)",
        inputs:
          ["lib/**/*.ex", "lib/**/*.erl", "build/gen/*.erl", "#{ehls}/lib/**/*", "#{ehls}/priv/backend/atomvm/lib/**/*",
           "#{@me}/scripts/build_ex.sh"] ++ for(p <- pkgs, do: "#{p}/lib/**/*"),
        exclude: junk,
        values: {project.app, project.start},
        outputs: ["build/#{project.app}.avm"],
        run: fn -> script(project, "build_ex.sh", [Atom.to_string(project.app), inspect(project.start)]) end
      }
    ]
  end

  @impl true
  def flash_images(project) do
    %{
      bitstream: Path.join(project.root, @bitstream),
      vm: Path.join(project.root, @vm),
      lib: Path.join(base(project), "build/host/libs/atomvmlib-zephyr-native.avm"),
      app: Path.join(project.build, "#{project.app}.avm")
    }
  end

  @impl true
  def run_needs, do: [:vm, :lib]

  @impl true
  def flash(project, parts, _opts) do
    args =
      Enum.flat_map(parts, fn
        :app -> ["app", Atom.to_string(project.app)]
        p -> [Atom.to_string(p)]
      end)

    script(project, "flash.sh", args)
  end

  @impl true
  def run(project, opts) do
    script(project, "run.sh", [Atom.to_string(project.app)], [{"SECONDS_RUN", to_string(opts[:seconds] || 10)}])
  end

  @impl true
  def console(project) do
    port = EHLS.Machine.get(project, :uart_port) || "/dev/ttyUSB1"
    Mix.shell().info("#{port}, 115200 baud (Ctrl+C twice to end)")

    reader =
      "import serial, sys\ns = serial.Serial(sys.argv[1], 115200)\n" <>
        "while True:\n    sys.stdout.buffer.write(s.read(s.in_waiting or 1)); sys.stdout.flush()\n"

    EHLS.Build.cmd!("python3", ["-u", "-c", reader, port])
  end

  @impl true
  def checks(project) do
    [
      {"the Gowin IDE (GOWIN_HOME)",
       fn ->
         case EHLS.Machine.get(project, :gowin_home) do
           nil -> {:error, "GOWIN_HOME not set and no ~/Gowin_* found"}
           d -> if File.exists?(Path.join(d, "IDE/bin/gw_sh")), do: :ok, else: {:error, "#{d} has no IDE/bin/gw_sh"}
         end
       end},
      {"openFPGALoader", fn -> exe("openFPGALoader") end},
      {"pyserial (python3 -c 'import serial')",
       fn ->
         case System.cmd("python3", ["-c", "import serial"], stderr_to_stdout: true) do
           {_, 0} -> :ok
           _ -> {:error, "pip install pyserial"}
         end
       end},
      {"the Zephyr workspace (ZEPHYR_WORKSPACE)",
       fn ->
         d = EHLS.Machine.get(project, :zephyr_workspace) || Path.expand("~/zephyrproject")
         if File.dir?(d), do: :ok, else: {:error, "no #{d}"}
       end},
      {"atomvm-tang25k set up (ATOMVM_TANG25K)",
       fn ->
         b = base(project)

         cond do
           b == nil -> {:error, "not a dependency and ATOMVM_TANG25K not set"}
           not set_up?(b) -> {:error, "#{b}: run its scripts/setup_litex.sh, setup_atomvm.sh, build_host.sh"}
           true -> :ok
         end
       end},
      {"the board's UART (UART_PORT)",
       fn ->
         p = EHLS.Machine.get(project, :uart_port) || "/dev/ttyUSB1"
         if File.exists?(p), do: :ok, else: {:error, "no #{p} (is the board connected?)"}
       end}
    ]
  end

  @impl true
  def board_gpio, do: Path.join(@me, "board_gpio.json")

  @doc false
  # the block packages: config :elixir_hls, blocks:, else the dependencies that depend on elixir-hls (directly or
  # through another), each after those it depends on
  def blocks(project) do
    project.config[:blocks] || derived_blocks()
  end

  defp derived_blocks do
    tree = Mix.Project.deps_tree()
    reaches? = fn reaches?, app -> Enum.any?(tree[app] || [], &(&1 == :elixir_hls or reaches?.(reaches?, &1))) end
    pkgs = for {app, _} <- tree, app not in @not_ours, reaches?.(reaches?, app), do: app
    order(Enum.sort(pkgs), tree, [])
  end

  defp order([], _tree, done), do: Enum.reverse(done)

  defp order(todo, tree, done) do
    {ready, rest} = Enum.split_with(todo, fn a -> Enum.all?(tree[a] || [], &(&1 not in todo)) end)
    if ready == [], do: Enum.reverse(done) ++ todo, else: order(rest, tree, Enum.reverse(ready) ++ done)
  end

  # every file of lib/ when one has `use EHLS` (a kernel's module may need the others at its compile: a table's
  # constants from another module), else none (no circuit)
  defp kernel_files(project) do
    files = Path.wildcard(Path.join(project.root, "lib/**/*.ex")) |> Enum.sort()

    if Enum.any?(files, &(File.read!(&1) =~ ~r/^\s*use EHLS\b/m)),
      do: Enum.map(files, &Path.relative_to(&1, project.root)),
      else: []
  end

  defp base(project), do: EHLS.Machine.get(project, :atomvm_tang25k) || EHLS.Project.dep_path(:atomvm_tang25k)

  defp set_up?(base), do: File.exists?(Path.join(base, "build/host/tools/packbeam/packbeam"))

  defp script(project, name, args, extra_env \\ []) do
    env =
      [{"APP_DIR", project.root}] ++
        EHLS.Machine.env(project) ++
        gowin_env(project.config[:gowin] || []) ++
        [{"EHLS_BLOCKS", Enum.join(blocks(project), ":")}] ++ extra_env

    EHLS.Build.cmd!(Path.join([@me, "scripts", name]), args, cd: project.root, env: env)
  end

  defp gowin_env(opts) do
    for {k, var} <- [place: "GW_PLACE", route: "GW_ROUTE"], v = opts[k], v != nil, do: {var, to_string(v)}
  end

  defp exe(name), do: if(System.find_executable(name), do: :ok, else: {:error, "#{name} not on PATH"})

  defp find_gowin do
    case Path.wildcard(Path.expand("~/Gowin_*/IDE/bin/gw_sh")) |> Enum.sort(:desc) do
      [gw | _] ->
        gw |> Path.dirname() |> Path.dirname() |> Path.dirname()

      [] ->
        if gw = System.find_executable("gw_sh"), do: gw |> Path.dirname() |> Path.dirname() |> Path.dirname()
    end
  end

  defp find_port do
    case Path.wildcard("/dev/serial/by-id/*-if01-port0") do
      [one] -> one
      _ -> nil
    end
  end

  defp find_base do
    d = EHLS.Project.dep_path(:atomvm_tang25k)
    if d && set_up?(d), do: d
  end

  defp find_zephyr do
    d = Path.expand("~/zephyrproject")
    if File.dir?(d), do: d
  end
end
