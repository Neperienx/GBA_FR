import subprocess
import os

# Path to the mGBA executable
mgba_path = r"C:\Program Files\mGBA\mgba.exe"  # or wherever it’s installed
# On Linux/Mac: mgba_path = "/usr/bin/mgba"  or  "/Applications/mGBA.app/Contents/MacOS/mGBA"

# Path to your ROM file
rom_path = r"C:\Users\nicol\Documents\GB_Emulator\Rouge Feu\Pokemon - Version Rouge Feu (France).gba"

# Launch mGBA with the ROM
subprocess.Popen([mgba_path, rom_path])
