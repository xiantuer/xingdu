@echo off
REM 星渡编译/运行脚本
REM 用法: run.bat          # 编译
REM        run.bat run     # 编译并运行
REM        run.bat help    # 查看帮助

setlocal
set PATH=C:\msys64\ucrt64\bin;C:\Users\26063\.cargo\bin;C:\Windows\system32;C:\Windows
set CC=C:\msys64\ucrt64\bin\gcc.exe
set CC_x86_64_pc_windows_gnu=C:\msys64\ucrt64\bin\gcc.exe

if "%1"=="run" goto :RUN
if "%1"=="help" goto :HELP

C:\msys64\usr\bin\bash.exe -lc "export PATH=/ucrt64/bin:/c/Users/26063/.cargo/bin:/usr/bin && cd /g/codex-AI-tools/xingdu && cargo build --target x86_64-pc-windows-gnu"
goto :EOF

:RUN
C:\msys64\usr\bin\bash.exe -lc "export PATH=/ucrt64/bin:/c/Users/26063/.cargo/bin:/usr/bin && cd /g/codex-AI-tools/xingdu && cargo run --target x86_64-pc-windows-gnu"
goto :EOF

:HELP
C:\msys64\usr\bin\bash.exe -lc "export PATH=/ucrt64/bin:/c/Users/26263/.cargo/bin:/usr/bin && cd /g/codex-AI-tools/xingdu && cargo run --target x86_64-pc-windows-gnu -- --help"