%============================================================================
% Filename		: mult_make.erl
% Description	: 编译函数类
% Author		: Wang, Xiong
% Email			: xiongwang@live.com
% Last Modified	: 10:49:50 AM  March 24, 2014
%============================================================================

%% 多进程编译,修改自otp/lib/tools/src/make.erl
%% 解析Emakefile,根据获取{mods, options}列表,
%% 按照次序编译每项(解决编译顺序的问题)
%% 其中mods也可以包含多个模块,当大于1个时,
%% 可以启动多个process进行编译,从而提高编译速度.
-module(mult_make).
-export([b/0, n/0, all/2, all/3, all/4, files/3, files/4]).
%-compile(export_all).

-include_lib("kernel/include/file.hrl").

-define(MakeOpts,[noexec,load,netload,noload]).
-define(Emakefile, "../script/Emakefile").
-define(ProcessSum, 4).

n() ->
    all({time(), now()}, compile).

b() ->
    all({time(), now()}, reload).


all(T, Flag) ->
	all(?ProcessSum, [netload], T, Flag).

all(Worker, T, Flag) when is_integer(Worker) ->
    all(Worker, [], T, Flag).

all(Worker, Options, T, Flag) when is_integer(Worker) ->
    {MakeOpts, CompileOpts} = sort_options(Options,[],[]),
    case read_emakefile(?Emakefile, CompileOpts) of
        Files when is_list(Files) ->
            spawn_link(fun() -> do_make_files(Worker, Files, MakeOpts, T, Flag) end);
        error ->
            error
    end.

files(Worker, Fs, Flag) ->
    files(Worker, Fs, [], Flag).

files(Worker, Fs0, Options, Flag) ->
    Fs = [filename:rootname(F,".erl") || F <- Fs0],
    {MakeOpts,CompileOpts} = sort_options(Options,[],[]),
    case get_opts_from_emakefile(Fs,?Emakefile,CompileOpts) of
	Files when is_list(Files) ->
            T = {time(), now()},
    	    do_make_files(Worker, Files, MakeOpts, T, Flag);	    
	error -> error
    end.

do_make_files(Worker, Fs, Opts, T, Flag) ->
    process(Fs, Worker, lists:member(noexec, Opts), load_opt(Opts), T, Flag).

sort_options([H|T],Make,Comp) ->
    case lists:member(H,?MakeOpts) of
	true ->
	    sort_options(T,[H|Make],Comp);
	false ->
	    sort_options(T,Make,[H|Comp])
    end;
sort_options([],Make,Comp) ->
    {Make,lists:reverse(Comp)}.

%%% Reads the given Emakefile and returns a list of tuples: {Mods,Opts}
%%% Mods is a list of module names (strings)
%%% Opts is a list of options to be used when compiling Mods
%%%
%%% Emakefile can contain elements like this:
%%% Mod.
%%% {Mod,Opts}.
%%% Mod is a module name which might include '*' as wildcard
%%% or a list of such module names
%%%
%%% These elements are converted to [{ModList,OptList},...]
%%% ModList is a list of modulenames (strings)
read_emakefile(Emakefile,Opts) ->
    case file:consult(Emakefile) of
	{ok, Emake} ->
	    transform(Emake,Opts,[],[]);
	{error,enoent} ->
	    %% No Emakefile found - return all modules in current 
	    %% directory and the options given at command line
	    Mods = [filename:rootname(F) ||  F <- filelib:wildcard("*.erl")],
	    [{Mods, Opts}];
	{error,Other} ->
	    io:format("make: Trouble reading Emakefile:~n~p~n",[Other]),
	    error
    end.

transform([{Mod,ModOpts}|Emake],Opts,Files,Already) ->
    case expand(Mod,Already) of
	[] -> 
	    transform(Emake,Opts,Files,Already);
	Mods -> 
	    transform(Emake,Opts,[{Mods,ModOpts++Opts}|Files],Mods++Already)
    end;
transform([Mod|Emake],Opts,Files,Already) ->
    case expand(Mod,Already) of
	[] -> 
	    transform(Emake,Opts,Files,Already);
	Mods ->
	    transform(Emake,Opts,[{Mods,Opts}|Files],Mods++Already)
    end;
transform([],_Opts,Files,_Already) ->
    lists:reverse(Files).

expand(Mod,Already) when is_atom(Mod) ->
    expand(atom_to_list(Mod),Already);
expand(Mods,Already) when is_list(Mods), not is_integer(hd(Mods)) ->
    lists:concat([expand(Mod,Already) || Mod <- Mods]);
expand(Mod,Already) ->
    case lists:member($*,Mod) of
	true -> 
	    Fun = fun(F,Acc) -> 
			  M = filename:rootname(F),
			  case lists:member(M,Already) of
			      true -> Acc;
			      false -> [M|Acc]
			  end
		  end,
	    lists:foldl(Fun, [], filelib:wildcard(Mod++".erl"));
	false ->
	    Mod2 = filename:rootname(Mod, ".erl"),
	    case lists:member(Mod2,Already) of
		true -> [];
		false -> [Mod2]
	    end
    end.

%%% Reads the given Emakefile to see if there are any specific compile 
%%% options given for the modules.
get_opts_from_emakefile(Mods,Emakefile,Opts) ->
    case file:consult(Emakefile) of
	{ok,Emake} ->
	    Modsandopts = transform(Emake,Opts,[],[]),
	    ModStrings = [coerce_2_list(M) || M <- Mods],
	    get_opts_from_emakefile2(Modsandopts,ModStrings,Opts,[]); 
	{error,enoent} ->
	    [{Mods, Opts}];
	{error,Other} ->
	    io:format("make: Trouble reading Emakefile:~n~p~n",[Other]),
	    error
    end.

get_opts_from_emakefile2([{MakefileMods,O}|Rest],Mods,Opts,Result) ->
    case members(Mods,MakefileMods,[],Mods) of
	{[],_} -> 
	    get_opts_from_emakefile2(Rest,Mods,Opts,Result);
	{I,RestOfMods} ->
	    get_opts_from_emakefile2(Rest,RestOfMods,Opts,[{I,O}|Result])
    end;
get_opts_from_emakefile2([],[],_Opts,Result) ->
    Result;
get_opts_from_emakefile2([],RestOfMods,Opts,Result) ->
    [{RestOfMods,Opts}|Result].
    
members([H|T],MakefileMods,I,Rest) ->
    case lists:member(H,MakefileMods) of
	true ->
	    members(T,MakefileMods,[H|I],lists:delete(H,Rest));
	false ->
	    members(T,MakefileMods,I,Rest)
    end;
members([],_MakefileMods,I,Rest) ->
    {I,Rest}.


%% Any flags that are not recognixed as make flags are passed directly
%% to the compiler.
%% So for example make:all([load,debug_info]) will make everything
%% with the debug_info flag and load it.
load_opt(Opts) ->
    case lists:member(netload,Opts) of
	true -> 
	    netload;
	false ->
	    case lists:member(load,Opts) of
		true ->
		    load;
		_ ->
		    noload
	    end
    end.

%% 处理
process([{[], _Opts}|Rest], Worker, NoExec, Load, T, Flag) ->
    process(Rest, Worker, NoExec, Load, T, Flag);
process([{L, Opts}|Rest], Worker, NoExec, Load, T, ReloadOrComp) ->
    Len = length(L),
    Worker2 = erlang:min(Len, Worker),
    io:format("\n======================   ~s   ======================\n"
             , [ReloadOrComp]),
    
    case catch do_worker(L, Opts, NoExec, Load, Worker2, ReloadOrComp) of
        error ->
            error;
        ok ->
            process(Rest, Worker, NoExec, Load, T, ReloadOrComp)
    end;
process([], _Worker, _NoExec, _Load, {{H0, M0, S0}, _} = T0, _Flag) ->
    T1 = {{H, M, S}, _Stamp} = {time(), now()},
    
    io:format("Started action at ~p:~p:~p,\t", [H0, M0, S0]),
    io:format("Ended at ~p:~p:~p\n", [H, M, S]), 
    [CM, CS] = get_time_cost(T0, T1),
    io:format("Time Cost: ~p min ~p seconds!~n", [CM, CS]),
	io:format("====================  accomplished!  ====================\n"),
    up_to_date.

get_time_cost({_, K0} = _T0, {_, K1} = _T1) ->
    Diff = timer:now_diff(K1, K0) div 1000000,
    Hours = Diff div 3600,
    Min = Hours * 60 + (Diff - Hours * 3600) div 60,
    Sec = Diff - Min * 60,
    [Min, Sec].

%% worker进行编译
do_worker(L, Opts, NoExec, Load, Worker, Flag) ->
    WorkerList = do_split_list(L, Worker),
    % 启动进程
    Ref = make_ref(),
    Pids =
    case Flag of
        compile ->
            [start_worker(E, Opts, NoExec, Load, self(), Ref) || E <- WorkerList];
        reload ->
            [start_reloader(E, Opts, NoExec, Load, self(), Ref) || E <- WorkerList]
    end,
    do_wait_worker(length(Pids), Ref, []).


%% 等待结果
do_wait_worker(0, _Ref, _) ->
    ok;
do_wait_worker(N, Ref, List) ->
    receive
        {ack, Ref} ->
            %io:format("Wait", []),
            do_wait_worker(N - 1, Ref, []);
        {error, Ref} ->
            io:format("error~n"),
            throw(error);
        {'EXIT', _P, _Reason} ->
            io:format("worker got EXIT signal...~n"),
            do_wait_worker(N, Ref, List);
        _Other ->
            io:format("receive unknown msg:~p~n", [_Other]),
            do_wait_worker(N, Ref, List)
    end.

%% 将L分割成最多包含N个子列表的列表
do_split_list(L, N) ->
    Len = length(L), 
    % 每个列表的元素数
    LLen = (Len + N - 1) div N,
    do_split_list(L, LLen, []).

do_split_list([], _N, Acc) ->
    lists:reverse(Acc);
do_split_list(L, N, Acc) ->
    {L2, L3} = lists:split(erlang:min(length(L), N), L),
    do_split_list(L3, N, [L2 | Acc]).

%% 启动worker进程
start_worker(L, Opts, NoExec, Load, Parent, Ref) ->
    Fun = 
    fun() ->
        [begin 
            case recompilep(coerce_2_list(F), NoExec, Load, Opts) of
                error ->
                    Parent ! {error, Ref},
                    exit(error);
 				{ok, M} ->
                    case code:soft_purge(M) of
                        true ->
                            io:format("HotUpdate Module:~p\n",[M]),
                            %% 连续加载两次 确认ERTS中的beam被更新
                            main:hot_update_code([M]),
                            main:hot_update_code([M]);
                        false ->
                            io:format("~p was occupied!\n\n", [M])
                    end,
 					ok;
                _ ->
                    ok
            end
        end || F <- L ],
        Parent ! {ack, Ref}
    end,
    spawn_link(Fun).

%% 启动worker进程
start_reloader(L, Opts, _NoExec, _Load, Parent, Ref) ->
    {T1, {H0, M0, _S0}} = calendar:local_time(),
    {H1, M1} = 
    case {H0 > 0, M0 > 15} of
        {true, true} ->
            {H0, M0 - 15};
        {true, false} ->
            {H0 - 1, M0 - 15 + 60};
        _ ->
            {0, 0}
    end,
    TorleranceTime = {T1, {H1, M1, 0}},
    Fun = fun() ->
                  [ begin 
                        case reload_recent_beam(coerce_2_list(F), Opts, TorleranceTime) of
                            error ->
                                Parent ! {error, Ref},
                                exit(error);
                            {reload, M} when M =/= 'mult_make'->
                                %% 连续加载两次 确认ERTS中的beam被更新
                                case code:soft_purge(M) of
                                    true ->
                                        io:format("reload : ~s~n", [M]),
                                        main:hot_update_code([M]),
                                        main:hot_update_code([M]);
                                    false ->
                                        ok
                                end;
                            _ ->
                                ok
                        end
                    end || F <- L ],
                  Parent ! {ack, Ref}
          end,
    spawn_link(Fun).




reload_recent_beam(File, Opts, Now) ->
    BaseName = filename:basename(File),
    ObjName = lists:append(BaseName, code:objfile_extension()),
    ObjFile = case lists:keysearch(outdir, 1, Opts) of
                  {value, {outdir, OutDir}} ->
                      filename:join(coerce_2_list(OutDir), ObjName);
                  false ->
                      ObjName
              end,
    case exists(ObjFile) of
        true -> do_reload1(File, ObjFile, Now);
        false -> not_need_to_reload
    end.


recompilep(File, NoExec, Load, Opts) ->
    ObjName = lists:append(filename:basename(File),
			   code:objfile_extension()),
    ObjFile = case lists:keysearch(outdir,1,Opts) of
		  {value,{outdir,OutDir}} ->
		      filename:join(coerce_2_list(OutDir),ObjName);
		  false ->
		      ObjName
	      end,
    case exists(ObjFile) of
	true ->
	    recompilep1(File, NoExec, Load, Opts, ObjFile);
	false ->
	    recompile(File, NoExec, Load, Opts)
    end.
 
do_reload1(File, ObjFile, Now) ->
    Basename = lists:append(File, ".erl"),
    {ok, Erl} = file:read_file_info(Basename),
    {ok, Obj} = file:read_file_info(ObjFile),
    #file_info{mtime = MtErl} = Erl,
    #file_info{mtime = MtObj} = Obj,

    Cond1 = MtErl < Now,
    Cond2 = MtObj < Now,
    
    Mod0 = filename:basename(Basename, ".erl"),
    Mod = list_to_atom(Mod0),
    case Cond1 andalso Cond2 of
        true ->
            not_need_to_reload;
        false ->
            {reload, Mod}
    end.

recompilep1(File, NoExec, Load, Opts, ObjFile) ->
    {ok, Erl} = file:read_file_info(lists:append(File, ".erl")),
    {ok, Obj} = file:read_file_info(ObjFile),
	 recompilep1(Erl, Obj, File, NoExec, Load, Opts).

recompilep1(#file_info{mtime=Te},
	    #file_info{mtime=To}, File, NoExec, Load, Opts) when Te>To ->
    recompile(File, NoExec, Load, Opts);
recompilep1(_Erl, #file_info{mtime=To}, File, NoExec, Load, Opts) ->
    recompile2(To, File, NoExec, Load, Opts).

%% recompile2(ObjMTime, File, NoExec, Load, Opts)
%% Check if file is of a later date than include files.
recompile2(ObjMTime, File, NoExec, Load, Opts) ->
    IncludePath = include_opt(Opts),
    case check_includes(lists:append(File, ".erl"), IncludePath, ObjMTime) of
	true ->
	    recompile(File, NoExec, Load, Opts);
	false ->
	    false
    end.

include_opt([{i,Path}|Rest]) ->
    [Path|include_opt(Rest)];
include_opt([_First|Rest]) ->
    include_opt(Rest);
include_opt([]) ->
    [].

%% recompile(File, NoExec, Load, Opts)
%% Actually recompile and load the file, depending on the flags.
%% Where load can be netload | load | noload

recompile(File, true, _Load, _Opts) ->
    io:format("Out of date: ~s\n",[File]);
recompile(File, false, noload, Opts) ->
    io:format("Recompile: ~s\n",[File]),
    compile:file(File, [report_errors, report_warnings, error_summary |Opts]);
recompile(File, false, load, Opts) ->
    io:format("Recompile: ~s\n",[File]),
    c:c(File, Opts);
recompile(File, false, netload, Opts) ->
    io:format("Recompile: ~s\n",[File]),
    c:nc(File, Opts).

exists(File) ->
    case file:read_file_info(File) of
	{ok, _} ->
	    true;
	_ ->
	    false
    end.

coerce_2_list(X) when is_atom(X) ->
    atom_to_list(X);
coerce_2_list(X) ->
    X.

%%% If you an include file is found with a modification
%%% time larger than the modification time of the object
%%% file, return true. Otherwise return false.
check_includes(File, IncludePath, ObjMTime) ->
    Path = [filename:dirname(File)|IncludePath], 
    case epp:open(File, Path, []) of
	{ok, Epp} ->
	    check_includes2(Epp, File, ObjMTime);
	_Error ->
	    false
    end.
    
check_includes2(Epp, File, ObjMTime) ->
    case epp:parse_erl_form(Epp) of
	{ok, {attribute, 1, file, {File, 1}}} ->
	    check_includes2(Epp, File, ObjMTime);
	{ok, {attribute, 1, file, {IncFile, 1}}} ->
	    case file:read_file_info(IncFile) of
		{ok, #file_info{mtime=MTime}} when MTime>ObjMTime ->
		    epp:close(Epp),
		    true;
		_ ->
		    check_includes2(Epp, File, ObjMTime)
	    end;
	{ok, _} ->
	    check_includes2(Epp, File, ObjMTime);
	{eof, _} ->
	    epp:close(Epp),
	    false;
	{error, _Error} ->
	    check_includes2(Epp, File, ObjMTime)
    end.
