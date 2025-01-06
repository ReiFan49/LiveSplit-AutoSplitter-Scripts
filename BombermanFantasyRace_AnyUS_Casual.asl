state ("duckstation-qt-x64-ReleaseLTCG", "any") {}
state ("duckstation-nogui-x64-ReleaseLTCG", "any") {}

startup {
  settings.Add("course_progression", true, "Split on Progression");
  settings.Add("split_on_bonus", true, "Split on Bonus", "course_progression");
  settings.Add("use_hyper_louie", true, "Need Hyper Louie (Beginner Route)", "course_progression");
  settings.Add("bomber_castle_unlock_check", true, "Check on Unlock Bomber Castle", "course_progression");

  vars.SUPER_NOISY_VERBOSE = false;

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
  vars.splitCache = new HashSet<string>();
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
  if (version == "")
    return false;

  if (vars.isDynamicAddress) {
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
  }

  if (vars.baseRAMAddress == IntPtr.Zero)
    return false;

  current.isTitleScreen = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x014971a) != 0;

  current.racePosition = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x0100f6);
  current.raceLapProgress = memory.ReadValue<sbyte>((IntPtr)vars.baseRAMAddress + 0x0100f7);
  current.raceStartBit = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x14e748);
  current.raceTrackID = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x148670);
  var raceTrackFlag = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x148714);
  current.raceTrackIsMirror = (raceTrackFlag & 1) != 0;
  current.raceTrackIsBonus = (raceTrackFlag & 2) != 0;
  var raceLapMax = current.raceTrackIsBonus ? 1 : 3;

  if (current.raceLapProgress >= 0) {
    current.raceTotalTime = memory.ReadValue<int>((IntPtr)vars.baseRAMAddress + 0x14ab38);
    int lapIndex = 0x14ab20 + 0x4 * current.raceLapProgress;
    
    if (current.raceLapProgress < raceLapMax)
      current.raceLapTime = memory.ReadValue<int>((IntPtr)vars.baseRAMAddress + lapIndex);
    else
      current.raceLapTime = memory.ReadValue<int>((IntPtr)vars.baseRAMAddress + (lapIndex - 0x4));
  }

  current.userControl = memory.ReadValue<ushort>((IntPtr)vars.baseRAMAddress + 0x14aaf4);
  current.userControlOnL2  = (current.userControl & (1 <<  0)) != 0;
  current.userControlOnR2  = (current.userControl & (1 <<  1)) != 0;
  current.userControlOnL1  = (current.userControl & (1 <<  2)) != 0;
  current.userControlOnR1  = (current.userControl & (1 <<  3)) != 0;
  current.userControlOnX   = (current.userControl & (1 <<  4)) != 0;
  current.userControlOnA   = (current.userControl & (1 <<  5)) != 0;
  current.userControlOnB   = (current.userControl & (1 <<  6)) != 0;
  current.userControlOnY   = (current.userControl & (1 <<  7)) != 0;
  current.userControlOnSel = (current.userControl & (1 <<  8)) != 0;
  current.userControlOnStr = (current.userControl & (1 << 11)) != 0;
  current.gameMode = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x1487e0);
  
  current.userCredit = memory.ReadValue<uint>((IntPtr)vars.baseRAMAddress + 0x14873c);
  current.userFlagUnlocked = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x148731);
  current.userFlagUnlockedMirror = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x148732);
  current.userFlagCleared = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x148733);
  current.userFlagClearedMirror = memory.ReadValue<byte>((IntPtr)vars.baseRAMAddress + 0x148734);
  current.userFlagRides = memory.ReadValue<ushort>((IntPtr)vars.baseRAMAddress + 0x148736);

  current.userIsUnlockedBomberCastle = (current.userFlagUnlocked & (1 << 6)) != 0;
  if ((current.userFlagCleared & (1 << 6)) != 0)
    current.userIsClearedBomberCastle = true;
  else
    current.userIsClearedBomberCastle = (
      current.raceTrackID == 6 &&
      !current.raceTrackIsMirror &&
      !current.raceTrackIsBonus &&
      current.racePosition == 1 &&
      current.raceLapProgress == 3 && old.raceLapProgress == 2
    );
}

start {
  if (game != null && vars.SUPER_NOISY_VERBOSE) print("start check");
  return current.gameMode == 0xff && current.userControlOnStr && old.isTitleScreen;
}

reset {
  if (game != null && vars.SUPER_NOISY_VERBOSE) print("reset check");
  return current.gameMode == 0xff && current.isTitleScreen && !old.isTitleScreen;
}

gameTime {
  if (game != null && vars.SUPER_NOISY_VERBOSE) print("gametime check");

  int delta = 0;
  int raceMaxLap = current.raceTrackIsBonus ? 1 : 3;

  if (current.raceTrackIsBonus)
    delta = old.raceLapTime - current.raceLapTime;
  else
    delta = current.raceTotalTime - old.raceTotalTime;

  // print(string.Format("Bonus Flag: {0} | Time: {1} {2} | Diff: {3} | Anchor: {4}", current.raceTrackIsMirror, current.raceTotalTime, current.raceLapTime, delta, anchorValue));

  if (vars.raceIgnoreTimeDelta) {
    if (current.raceLapProgress == raceMaxLap && old.raceLapProgress == current.raceLapProgress - 1)
      delta -= 1;
    else
      delta = 0;
  }

  current.totalCourseTime += delta;

  var deltaTicks = (long)(current.totalCourseTime * TimeSpan.TicksPerSecond / 30);
  return TimeSpan.FromTicks(deltaTicks);
}

isLoading {
  if (game != null && vars.SUPER_NOISY_VERBOSE) print("loading check");

  if (current.raceStartBit == 0 && old.raceStartBit > 0)
    vars.raceIgnoreTimeDelta = false;

  if (current.raceLapProgress < old.raceLapProgress || old.raceLapProgress < 0)
    vars.raceIgnoreTimeDelta = true;

  int maxLap = current.raceTrackIsBonus ? 1 : 3;
  if (current.raceLapProgress == maxLap && old.raceLapProgress == current.raceLapProgress - 1)
    vars.raceIgnoreTimeDelta = true;

  return true;
}

split {
  if (game != null && vars.SUPER_NOISY_VERBOSE) print("split check");

  int actualTrackID = 255;
  int moneyRequired = 0;
  bool isClearBonus = false;

  int previousClearFlags = old.userFlagCleared | (old.userFlagClearedMirror << 8);
  int currentClearFlags = current.userFlagCleared | (current.userFlagClearedMirror << 8);

  if (game != null) {
    actualTrackID = current.raceTrackID | (current.raceTrackIsMirror ? 8 : 0);

    if (current.raceTrackIsBonus && current.raceLapProgress == 1 && old.raceLapProgress == 0) {
      print(string.Format("Pop the Bonus Flag for Track {0}", actualTrackID));
      isClearBonus = true;
      vars.bonusTrackFlag[actualTrackID] = false;
    } else if (!current.raceTrackIsBonus && current.raceLapProgress == 3 && old.raceLapProgress == 2 && current.racePosition == 1 && previousClearFlags != currentClearFlags) {
      print(string.Format("Register Bonus Flag for Track {0}", actualTrackID));
      vars.bonusTrackFlag[actualTrackID] = true;
    }
  }

  if (settings["course_progression"]) {
    var trackBit = 1 << current.raceTrackID;

    var oldCleared = (old.userFlagCleared & trackBit) != 0;
    var currentCleared = (current.userFlagCleared & trackBit) != 0;

    if (!vars.canUnlockCastleFlag && settings["bomber_castle_unlock_check"]) {
      if ((current.userFlagUnlocked & (1 << 1)) == 0) moneyRequired +=  100;
      if ((current.userFlagUnlocked & (1 << 2)) == 0) moneyRequired +=  400;
      if ((current.userFlagUnlocked & (1 << 3)) == 0) moneyRequired +=  900;
      if ((current.userFlagUnlocked & (1 << 4)) == 0) moneyRequired += 1500;
      if ((current.userFlagUnlocked & (1 << 5)) == 0) moneyRequired += 3000;
      if ((current.userFlagUnlocked & (1 << 6)) == 0) moneyRequired += 4600;

      if (settings["use_hyper_louie"] && ((current.userFlagRides & (1 << 4)) == 0)) moneyRequired += 8000;

      var canUnlockCastleOld     = old.userCredit >= moneyRequired;
      var canUnlockCastleCurrent = current.userCredit >= moneyRequired;
      if(canUnlockCastleCurrent && !canUnlockCastleOld && moneyRequired > 0) {
        vars.canUnlockCastleFlag = true;
        return true;
      }
    }

    if (settings["split_on_bonus"]) {
      if (
        current.raceTrackIsBonus &&
        isClearBonus
      ) return true;
    } else {
      if (currentCleared && !oldCleared) return true;
    }
  }

  return current.userIsClearedBomberCastle;
}

onStart {
  current.totalCourseTime = 0;
  vars.bonusTrackFlag = new bool[16];
  vars.canUnlockCastleFlag = false;
}
