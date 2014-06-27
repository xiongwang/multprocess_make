@echo off

set NODE=1
set COOKIE=sm_new
set IP=172.16.223.72
set NODE_NAME=game_dev_%NODE%@%IP%
set UPDATE_NODE_NAME=update_game_%NODE%@%IP%
set EBIN_DIRS=ebin ebin/game ebin/data ebin/base

set ERL=E:\program\erl5.10.3\bin\erl.exe
set ERLC=E:\program\erl5.10.3\bin\erlc.exe
set WERL=E:\program\erl5.10.3\bin\werl.exe

cd ..

:%ERLC% -o ebin/base scripts/beam_pusher.erl
start %WERL% -pa %EBIN_DIRS% -name %UPDATE_NODE_NAME% -setcookie %COOKIE% -s beam_pusher start %NODE_NAME%
:pause
