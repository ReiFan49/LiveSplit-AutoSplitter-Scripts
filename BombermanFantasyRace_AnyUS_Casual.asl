state ("duckstation-qt-x64-ReleaseLTCG", "any") {}
state ("duckstation-nogui-x64-ReleaseLTCG", "any") {}

startup {
  settings.Add("course_progression", true, "Split on Progression");
  settings.Add("split_on_bonus", true, "Split on Bonus", "course_progression");
  settings.Add("use_hyper_louie", true, "Need Hyper Louie (Beginner Route)", "course_progression");
  settings.Add("bomber_castle_unlock_check", true, "Check on Unlock Bomber Castle", "course_progression");

  vars.SUPER_NOISY_VERBOSE = false;

  /* CONSTANTS */
  // TRACK CONSTANTS
  vars.TR_CIRCUIT  = 0;
  vars.TR_COASTER  = 1;
  vars.TR_ISLE     = 2;
  vars.TR_BAKUDAN  = 3;
  vars.TR_EXPRESS  = 4;
  vars.TR_DYNAMITE = 5;
  vars.TR_CASTLE   = 6;
  vars.TR_SPACEWAY = 7;

  // TRACK BITS
  vars.TRB_CIRCUIT  = 1 << vars.TR_CIRCUIT;
  vars.TRB_COASTER  = 1 << vars.TR_COASTER;
  vars.TRB_ISLE     = 1 << vars.TR_ISLE;
  vars.TRB_BAKUDAN  = 1 << vars.TR_BAKUDAN;
  vars.TRB_EXPRESS  = 1 << vars.TR_EXPRESS;
  vars.TRB_DYNAMITE = 1 << vars.TR_DYNAMITE;
  vars.TRB_CASTLE   = 1 << vars.TR_CASTLE;
  vars.TRB_SPACEWAY = 1 << vars.TR_SPACEWAY;

  // TRACK MIRROR BITS
  vars.TRB_MCIRCUIT  =  vars.TRB_CIRCUIT << 8;
  vars.TRB_MCOASTER  =  vars.TRB_COASTER << 8;
  vars.TRB_MISLE     =     vars.TRB_ISLE << 8;
  vars.TRB_MBAKUDAN  =  vars.TRB_BAKUDAN << 8;
  vars.TRB_MEXPRESS  =  vars.TRB_EXPRESS << 8;
  vars.TRB_MDYNAMITE = vars.TRB_DYNAMITE << 8;
  vars.TRB_MCASTLE   =   vars.TRB_CASTLE << 8;
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

  Func<int, bool> funcApplyBonusFlag = (actualTrackID) => {
    if (current.raceTrackIsBonus && current.raceLapProgress == 1 && old.raceLapProgress == 0) {
      print(string.Format("Pop the Bonus Flag for Track {0}", actualTrackID));
      vars.bonusTrackFlag[actualTrackID] = false;

      return true;
    } else if (!current.raceTrackIsBonus && current.raceLapProgress == 3 && old.raceLapProgress == 2 && current.racePosition == 1) {
      print(string.Format("Register Bonus Flag for Track {0}", actualTrackID));
      vars.bonusTrackFlag[actualTrackID] = true;
    }

    return false;
  };

  Func<bool> funcCheckPreCastleNormal = () => {
    int moneyRequired = 0;

    if ((current.userFlagCleared & 0x3f) != 0x3f) return false;

    if ((current.userFlagUnlocked &  vars.TRB_COASTER) == 0) moneyRequired +=  100;
    if ((current.userFlagUnlocked &     vars.TRB_ISLE) == 0) moneyRequired +=  400;
    if ((current.userFlagUnlocked &  vars.TRB_BAKUDAN) == 0) moneyRequired +=  900;
    if ((current.userFlagUnlocked &  vars.TRB_EXPRESS) == 0) moneyRequired += 1500;
    if ((current.userFlagUnlocked & vars.TRB_DYNAMITE) == 0) moneyRequired += 3000;
    if ((current.userFlagUnlocked &   vars.TRB_CASTLE) == 0) moneyRequired += 4600;

    if (settings["use_hyper_louie"] && ((current.userFlagRides & (1 << 4)) == 0)) moneyRequired += 8000;

    var canUnlockCastleOld     = old.userCredit >= moneyRequired;
    var canUnlockCastleCurrent = current.userCredit >= moneyRequired;
    if(canUnlockCastleCurrent && !canUnlockCastleOld && moneyRequired > 0) {
      vars.canUnlockCastleFlag = true;
      return true;
    }

    return false;
  };

  vars.fUpdateDynamicAddress = funcUpdateDynamicAddress;
  vars.fOnClearRace = funcApplyBonusFlag;
  vars.fOnUnlockableNormalCastle = funcCheckPreCastleNormal;
  // FUNCTIONS - END

  if (version == "")
    return false;

  if (vars.isDynamicAddress)
    vars.fUpdateDynamicAddress();

  if (vars.baseRAMAddress == IntPtr.Zero)
    return false;

  // Not an accurate way to describe Title Screen.
  // This value also set anywhere else like during the race.
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
  current.userFlagUnlocked = memory.ReadValue<short>((IntPtr)vars.baseRAMAddress + 0x148731);
  current.userFlagCleared = memory.ReadValue<short>((IntPtr)vars.baseRAMAddress + 0x148733);
  current.userFlagRides = memory.ReadValue<ushort>((IntPtr)vars.baseRAMAddress + 0x148736);

  current.userIsUnlockedBomberCastle = (current.userFlagUnlocked & vars.TRB_CASTLE) != 0;
  if ((current.userFlagCleared & vars.TRB_CASTLE) != 0)
    current.userIsClearedBomberCastle = true;
  else
    current.userIsClearedBomberCastle = (
      current.raceTrackID == vars.TR_CASTLE &&
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
  /*
    Rewire on how the flag are actually assigned.

    userFlagCleared are updated after fading out from race screen.
    * if bonus existed, clear flag will not be applied first
  */

  if (game != null && vars.SUPER_NOISY_VERBOSE) print("split check");

  int actualTrackID = 255;
  bool isClearBonus = false;

  int currentClearFlags = current.userFlagCleared;
  bool currentTrackClearFlag = false;

  if (current.raceLapProgress >= 0) {
    actualTrackID = current.raceTrackID | (current.raceTrackIsMirror ? 8 : 0);
    currentTrackClearFlag = (currentClearFlags & (1 << actualTrackID)) != 0;

    isClearBonus = vars.fOnClearRace(actualTrackID);
  }

  if (settings["course_progression"]) {
    var trackBit = 1 << current.raceTrackID;

    var oldCleared = (old.userFlagCleared & trackBit) != 0;
    var currentCleared = (current.userFlagCleared & trackBit) != 0;

    if (
      !vars.canUnlockCastleFlag &&
      settings["bomber_castle_unlock_check"] &&
      vars.fOnUnlockableNormalCastle()
    ) {
      return true;
    }

    if (settings["split_on_bonus"]) {
      if (
        current.raceTrackIsBonus &&
        !currentTrackClearFlag && // make sure to not split on already cleared track
        (isClearBonus || current.raceLapProgress < 0)
      ) return true;
    } else {
      if (
        !current.raceTrackIsBonus &&
        !currentTrackClearFlag &&
        current.racePosition == 1
      ) return true;
    }
  }

  return current.userIsClearedBomberCastle;
}

onStart {
  current.totalCourseTime = 0;
  vars.bonusTrackFlag = new bool[16];
  vars.canUnlockCastleFlag = false;
}
