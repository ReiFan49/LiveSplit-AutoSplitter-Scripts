state ("duckstation-qt-x64-ReleaseLTCG", "any") {}
state ("duckstation-nogui-x64-ReleaseLTCG", "any") {}

startup {
  /* CONSTANTS */
  vars.GAME_SERIAL = "SLPS-01489";

  // TRACK CONSTANTS

  // TRACK BITS

  // CONSTANTS - END

  /* Dynamic Finder */
  Func<IEnumerable<MemoryBasicInformation>, IntPtr> defaultFinder = (memoryPages) => IntPtr.Zero;
  vars.dynamicFinder = defaultFinder;
  vars.dynamicFinderTimer = new Stopwatch();

  vars.duckstationProcesses = new List<string> {
    "duckstation-qt-x64-ReleaseLTCG",
    "duckstation-nogui-x64-ReleaseLTCG",
  };
  vars.isDuckstation = false;

  vars.isDynamicAddress = false;
  vars.isDynamicAddressFound = false;

  vars.baseRAMAddress = IntPtr.Zero;
  // Dynamic Finder - END
}

init {
  var module = modules.First();

  if (vars.duckstationProcesses.Contains(game.ProcessName)) {
    print("Duckstation detected");

    Func<IEnumerable<MemoryBasicInformation>, IntPtr> duckstationFinder = (pages) => {
      var memoryBlock = pages.Where(page => page.Type == MemPageType.MEM_MAPPED && page.RegionSize == (UIntPtr)0x200000).FirstOrDefault().BaseAddress;
      if (memoryBlock != IntPtr.Zero) {
        print("Found Duckstation memory at: " + memoryBlock);
        return memoryBlock;
      }

      memoryBlock = pages.Where(page => page.Type == MemPageType.MEM_MAPPED && page.RegionSize == (UIntPtr)0x796000).FirstOrDefault().BaseAddress;
      if (memoryBlock != IntPtr.Zero) {
        print("Found Duckstation memory at: (internal) " + memoryBlock);
        return memoryBlock - 0x06a000;
      }

      return IntPtr.Zero;
    };

    vars.dynamicFinder = duckstationFinder;
    vars.isDuckstation = true;
    vars.isDynamicAddress = true;
    vars.baseRAMAddress = IntPtr.Zero;
    version = "any";
  }

  refreshRate = 60;
}

update {
  /* Functions */
  Func<bool> funcUpdateDynamicAddress = () => {
    if (!vars.isDynamicAddressFound) {
      if(vars.dynamicFinderTimer.IsRunning && vars.dynamicFinderTimer.ElapsedMilliseconds <= 500)
        return false;

      print("Looking for dynamic memory block...");

      vars.dynamicFinderTimer.Start();

      vars.baseRAMAddress = vars.dynamicFinder(game.MemoryPages(true));
      if (vars.baseRAMAddress == IntPtr.Zero) {
        vars.dynamicFinderTimer.Restart();
        return false;
      }

      vars.dynamicFinderTimer.Reset();
      vars.isDynamicAddressFound = true;
    }

    IntPtr temp1 = vars.baseRAMAddress, temp2 = IntPtr.Zero;
    if(!game.ReadPointer(temp1, out temp2)) {
      print("Lost hold of current RAM address...");
      vars.isDynamicAddressFound = false;
      vars.baseRAMAddress = IntPtr.Zero;
    }

    return true;
  };

  vars.fUpdateDynamicAddress = funcUpdateDynamicAddress;
  // FUNCTIONS - END

  if (version == "")
    return false;

  if (vars.isDynamicAddress)
    vars.fUpdateDynamicAddress();

  if (vars.baseRAMAddress == IntPtr.Zero)
    return false;

  byte[] gameSerial = new byte[10];
  if(!memory.ReadBytes((IntPtr)vars.baseRAMAddress + 0x00ba94, 10, out gameSerial)) return false;
  if(Encoding.Default.GetString(gameSerial) != vars.GAME_SERIAL) return false;

  // This value also set anywhere else like during the race.
  vars.configLapTotal = memory.ReadValue<sbyte>((IntPtr)vars.baseRAMAddress + 0x082fb8);
  current.racePosition = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x0fe5d5);
  current.raceLapProgress = memory.ReadValue<sbyte>((IntPtr)vars.baseRAMAddress + 0x0fe5d4);
  current.raceTotalTime = memory.ReadValue<int>((IntPtr)vars.baseRAMAddress + 0x111b40);
  // Lap Time: 0x111a1c + lapCount * 4
}

gameTime {
  int delta = 0;

  if (current.raceLapProgress >= 0 && old.raceLapProgress >= 0 && current.raceLapProgress <= vars.configLapTotal)
    delta = current.raceTotalTime - old.raceTotalTime;

  // This is doesn't seem to be a static memory usage, or
  // perhaps the memory is cleaned up after use.
  // Either way, delta tolerance is 0xffff or about 35 minutes.
  if (Math.Abs(delta) > 0xffff)
    delta = 0;

  current.totalCourseTime += delta;

  var deltaTicks = (long)(current.totalCourseTime * TimeSpan.TicksPerSecond / 30);
  return TimeSpan.FromTicks(deltaTicks);
}

isLoading {
  return true;
}

split {
  if (current.raceLapProgress > vars.configLapTotal && old.raceLapProgress == current.raceLapProgress - 1 && current.racePosition == 1) return true;
}

onStart {
  current.totalCourseTime = 0;
}
