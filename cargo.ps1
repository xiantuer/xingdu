$env:PATH = "C:\msys64\ucrt64\bin;C:\Users\26063\.cargo\bin;$env:PATH"
$env:CC = "C:\msys64\ucrt64\bin\gcc.exe"
$env:CC_x86_64_pc_windows_gnu = "C:\msys64\ucrt64\bin\gcc.exe"

C:\msys64\usr\bin\bash.exe -lc "export PATH=/ucrt64/bin:/c/Users/26063/.cargo/bin:/usr/bin && cd /g/codex-AI-tools/xingdu && cargo $args"