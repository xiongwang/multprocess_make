%=============================================================================
%       Filename:  beam_pusher.erl
%           Desc:  推送新的beam到节点
%         Author:  Wang Xiong
%          Email:  xiongwang@live.com
%       Homepage:  www.geekxiong.com
%  Last Modified:  2014-06-19 13:08:58
%=============================================================================

%% 修改自github.com/xiongwang/multprocess_make
%%
-module(beam_pusher).
-behaviour(gen_server).

-include_lib("kernel/include/file.hrl").

-define(MakeOpts,[noexec,load,netload,noload]).
-define(DEFAULT_PROCESS_NUM, 4).
-define(DEFAULT_CHECK_TIME, 1 * 1000).

%% ====================================================================
%% API functions
%% ====================================================================
-export([init/1, handle_call/3, handle_cast/2, handle_info/2
         , terminate/2, code_change/3 ]).
-export([start/1, all/3]).

start(Node) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Node, []).

%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, {previous_check_time = 0
               ,target_node = 'null_node'}
       ).

%% init/1
%% ====================================================================
-spec init(Args :: term()) -> Result when
	Result :: {ok, State}
			| {ok, State, Timeout}
			| {ok, State, hibernate}
			| {stop, Reason :: term()}
			| ignore,
	State :: term(),
	Timeout :: non_neg_integer() | infinity.
%% ====================================================================
init([Node]) ->
    %Node = list_to_atom(Node0),
    NewState = #state{ previous_check_time = {date(), time()}
                       , target_node = Node
                     },

    erlang:send_after(?DEFAULT_CHECK_TIME, self(), {'do_check'}),
    io:format("TargetNode = ~p~n", [Node]),          
    {ok, NewState}.


%% handle_call/3
%% ====================================================================
-spec handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: term()) -> Result when
	Result :: {reply, Reply, NewState}
			| {reply, Reply, NewState, Timeout}
			| {reply, Reply, NewState, hibernate}
			| {noreply, NewState}
			| {noreply, NewState, Timeout}
			| {noreply, NewState, hibernate}
			| {stop, Reason, Reply, NewState}
			| {stop, Reason, NewState},
	Reply :: term(),
	NewState :: term(),
	Timeout :: non_neg_integer() | infinity,
	Reason :: term().
%% ====================================================================
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.


%% handle_cast/2
%% ====================================================================
-spec handle_cast(Request :: term(), State :: term()) -> Result when
	Result :: {noreply, NewState}
			| {noreply, NewState, Timeout}
			| {noreply, NewState, hibernate}
			| {stop, Reason :: term(), NewState},
	NewState :: term(),
	Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_cast(_Msg, State) ->
    {noreply, State}.


%% handle_info/2
%% ====================================================================
-spec handle_info(Info :: timeout | term(), State :: term()) -> Result when
	Result :: {noreply, NewState}
			| {noreply, NewState, Timeout}
			| {noreply, NewState, hibernate}
			| {stop, Reason :: term(), NewState},
	NewState :: term(),
	Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_info({'do_check'}, State) ->
    NowDateTime = {date(), time()},
    
    all(State#state.target_node, 
        State#state.previous_check_time,
        NowDateTime
       ),
    erlang:send_after(?DEFAULT_CHECK_TIME, self(), {'do_check'}),
    {noreply, State#state{previous_check_time = NowDateTime}};

handle_info(_Msg, State) ->
    {noreply, State}.

%% terminate/2
%% ====================================================================
-spec terminate(Reason, State :: term()) -> Any :: term() when
	Reason :: normal
			| shutdown
			| {shutdown, term()}
			| term().
%% ====================================================================
terminate(_Reason, _State) ->
    ok.


%% code_change/3
%% ====================================================================
-spec code_change(OldVsn, State :: term(), Extra :: term()) -> Result when
	Result :: {ok, NewState :: term()} | {error, Reason :: term()},
	OldVsn :: Vsn | {down, Vsn},
	Vsn :: term().
%% ====================================================================
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% ====================================================================
%% Internal functions
%% ====================================================================

all(Node, LastT, NowT) ->
    all(?DEFAULT_PROCESS_NUM, [], Node, LastT, NowT).

all(Worker, Options, Node, LastT, NowT) when is_integer(Worker) ->
    {MakeOpts, CompileOpts} = sort_options(Options,[],[]),
    case read_emakefile('Emakefile', CompileOpts) of
        Files when is_list(Files) ->
            do_make_files(Worker, Files, MakeOpts, Node, LastT, NowT);
        error ->
            error
    end.

%files(Worker, Fs) ->
%    files(Worker, Fs, []).
%
%files(Worker, Fs0, Options) ->
%    Fs = [filename:rootname(F,".erl") || F <- Fs0],
%    {MakeOpts,CompileOpts} = sort_options(Options,[],[]),
%    case get_opts_from_emakefile(Fs,'Emakefile',CompileOpts) of
%	Files when is_list(Files) ->
%	    do_make_files(Worker, Files,MakeOpts, []);	    
%	error -> error
%    end.

do_make_files(Worker, Fs, Opts, Node, LastT, NowT) ->
    process(Fs, Worker, lists:member(noexec, Opts), load_opt(Opts), Node, LastT, NowT).

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
	    io:format("make: Trouble reading 'Emakefile':~n~p~n",[Other]),
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

%%%%% Reads the given Emakefile to see if there are any specific compile 
%%%%% options given for the modules.
%%get_opts_from_emakefile(Mods,Emakefile,Opts) ->
%%    case file:consult(Emakefile) of
%%	{ok,Emake} ->
%%	    Modsandopts = transform(Emake,Opts,[],[]),
%%	    ModStrings = [coerce_2_list(M) || M <- Mods],
%%	    get_opts_from_emakefile2(Modsandopts,ModStrings,Opts,[]); 
%%	{error,enoent} ->
%%	    [{Mods, Opts}];
%%	{error,Other} ->
%%	    io:format("make: Trouble reading 'Emakefile':~n~p~n",[Other]),
%%	    error
%%    end.

%%get_opts_from_emakefile2([{MakefileMods,O}|Rest],Mods,Opts,Result) ->
%%    case members(Mods,MakefileMods,[],Mods) of
%%	{[],_} -> 
%%	    get_opts_from_emakefile2(Rest,Mods,Opts,Result);
%%	{I,RestOfMods} ->
%%	    get_opts_from_emakefile2(Rest,RestOfMods,Opts,[{I,O}|Result])
%%    end;
%%get_opts_from_emakefile2([],[],_Opts,Result) ->
%%    Result;
%%get_opts_from_emakefile2([],RestOfMods,Opts,Result) ->
%%    [{RestOfMods,Opts}|Result].
%%    
%%members([H|T],MakefileMods,I,Rest) ->
%%    case lists:member(H,MakefileMods) of
%%	true ->
%%	    members(T,MakefileMods,[H|I],lists:delete(H,Rest));
%%	false ->
%%	    members(T,MakefileMods,I,Rest)
%%    end;
%%members([],_MakefileMods,I,Rest) ->
%%    {I,Rest}.


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
process([{[], _Opts}|Rest], Worker, NoExec, Load, Node, LastT, NowT) ->
    process(Rest, Worker, NoExec, Load, Node, LastT, NowT);
process([{L, Opts}|Rest], Worker, NoExec, Load, Node, LastT, NowT) ->
    Len = length(L),
    Worker2 = erlang:min(Len, Worker),
    case catch do_worker(L, Opts, NoExec, Load, Worker2, Node, LastT, NowT) of
        error ->
            error;
        ok ->
            process(Rest, Worker, NoExec, Load, Node, LastT, NowT)
    end;
process([], _Worker, _NoExec, _Load, _Node, _LastT, _NowT) ->
    up_to_date.

%% worker进行编译
do_worker(L, Opts, NoExec, Load, Worker, Node, LastT, NowT) ->
    WorkerList = do_split_list(L, Worker),
    %io:format("worker:~p worker list(~p)~n", [Worker, length(WorkerList)]),
    % 启动进程
    Ref = make_ref(),
    Pids =
    [begin
        start_pusher(E, Opts, NoExec, Load, self(), Ref, Node, LastT, NowT)
    end || E <- WorkerList],
    do_wait_worker(length(Pids), Ref, [], Node).

%% 等待结果
do_wait_worker(0, _Ref, _, _) ->
    ok;
do_wait_worker(N, Ref, List, Node) ->
    receive
%% 		{new, M, Ref} ->
%% 			do_wait_worker(N, Ref, [M|List], Node);
        {ack, Ref} ->
%% 			rpc:cast(Node, main, hot_update_code, [List]),
            do_wait_worker(N - 1, Ref, [], Node);
        {error, Ref} ->
%% 			rpc:cast(Node, main, hot_update_code, [List]),
            throw(error);
        {'EXIT', _P, _Reason} ->
            do_wait_worker(N, Ref, List, Node);
        _Other ->
            io:format("receive unknown msg:~p~n", [_Other]),
            do_wait_worker(N, Ref, List, Node)
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
start_pusher(L, Opts, _NoExec, _Load, Parent, Ref, Node, LastT, NowT) ->
    Fun = 
    fun() ->
        [begin 
            case check_modified_beam(coerce_2_list(F), Opts, LastT, NowT) of
                error ->
                    Parent ! {error, Ref},
                    exit(error);
				{reload, M} ->
%% 					Parent ! {new, M, Ref};
					if is_atom(Node) ->
						   io:format("Pushed Module: ~p\n",[M]),
						   rpc:cast(Node, c, l, [M]);
					   true ->
                           io:format("Node was not an atom!\n"),
						   ok
					end;
                _ ->
                    ok
            end
        end || F <- L],
        Parent ! {ack, Ref}
    end,
    spawn_link(Fun).

check_modified_beam(File, Opts, LastT, NowT) ->
    BaseName = filename:basename(File),
    ObjName = lists:append(BaseName, code:objfile_extension()),
    ObjFile = case lists:keysearch(outdir, 1, Opts) of
                  {value, {outdir, OutDir}} ->
                      filename:join(coerce_2_list(OutDir), ObjName);
                  false ->
                      ObjName
              end,
    case exists(ObjFile) of
        true -> do_reload1(File, ObjFile, LastT, NowT);
        false -> io:format("File ~w did NOT exists!\n", [ObjFile]),
                 not_need_to_reload
    end.

do_reload1(File, ObjFile, LastT, NowT) ->
    Basename = lists:append(File, ".erl"),
    {ok, Obj} = file:read_file_info(ObjFile),
    #file_info{mtime = MtObj} = Obj,

    Cond1 = MtObj > LastT,
    Cond2 = MtObj < NowT,
    
    Mod0 = filename:basename(Basename, ".erl"),
    Mod = list_to_atom(Mod0),
    
    case Cond1 andalso Cond2 of
        true ->
            {reload, Mod};
        false ->
            not_need_to_reload
    end.



%%recompilep(File, NoExec, Load, Opts) ->
%%    ObjName = lists:append(filename:basename(File),
%%			   code:objfile_extension()),
%%    ObjFile = case lists:keysearch(outdir,1,Opts) of
%%		  {value,{outdir,OutDir}} ->
%%		      filename:join(coerce_2_list(OutDir),ObjName);
%%		  false ->
%%		      ObjName
%%	      end,
%%    case exists(ObjFile) of
%%	true ->
%%	    recompilep1(File, NoExec, Load, Opts, ObjFile);
%%	false ->
%%	    recompile(File, NoExec, Load, Opts)
%%    end.
%% 
%%recompilep1(File, NoExec, Load, Opts, ObjFile) ->
%%    {ok, Erl} = file:read_file_info(lists:append(File, ".erl")),
%%    {ok, Obj} = file:read_file_info(ObjFile),
%%	 recompilep1(Erl, Obj, File, NoExec, Load, Opts).

%%recompilep1(#file_info{mtime=Te},
%%	    #file_info{mtime=To}, File, NoExec, Load, Opts) when Te>To ->
%%    recompile(File, NoExec, Load, Opts);
%%recompilep1(_Erl, #file_info{mtime=To}, File, NoExec, Load, Opts) ->
%%%    recompile2(To, File, NoExec, Load, Opts).
%%    no_need_to_reload.

%%%% recompile2(ObjMTime, File, NoExec, Load, Opts)
%%%% Check if file is of a later date than include files.
%%recompile2(ObjMTime, File, NoExec, Load, Opts) ->
%%    IncludePath = include_opt(Opts),
%%    case check_includes(lists:append(File, ".erl"), IncludePath, ObjMTime) of
%%	true ->
%%	    recompile(File, NoExec, Load, Opts);
%%	false ->
%%	    false
%%    end.

%%include_opt([{i,Path}|Rest]) ->
%%    [Path|include_opt(Rest)];
%%include_opt([_First|Rest]) ->
%%    include_opt(Rest);
%%include_opt([]) ->
%%    [].

%% recompile(File, NoExec, Load, Opts)
%% Actually recompile and load the file, depending on the flags.
%% Where load can be netload | load | noload

%%recompile(File, true, _Load, _Opts) ->
%%    io:format("Out of date: ~s\n",[File]);
%%recompile(File, false, noload, Opts) ->
%%    io:format("Recompile: ~s\n",[File]),
%%    compile:file(File, [report_errors, report_warnings, error_summary |Opts]);
%%recompile(File, false, load, Opts) ->
%%    io:format("Recompile: ~s\n",[File]),
%%    c:c(File, Opts);
%%recompile(File, false, netload, Opts) ->
%%    io:format("Recompile: ~s\n",[File]),
%%    c:nc(File, Opts).

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

%%%%% If you an include file is found with a modification
%%%%% time larger than the modification time of the object
%%%%% file, return true. Otherwise return false.
%%check_includes(File, IncludePath, ObjMTime) ->
%%    Path = [filename:dirname(File)|IncludePath], 
%%    case epp:open(File, Path, []) of
%%	{ok, Epp} ->
%%	    check_includes2(Epp, File, ObjMTime);
%%	_Error ->
%%	    false
%%    end.
%%    
%%check_includes2(Epp, File, ObjMTime) ->
%%    case epp:parse_erl_form(Epp) of
%%	{ok, {attribute, 1, file, {File, 1}}} ->
%%	    check_includes2(Epp, File, ObjMTime);
%%	{ok, {attribute, 1, file, {IncFile, 1}}} ->
%%	    case file:read_file_info(IncFile) of
%%		{ok, #file_info{mtime=MTime}} when MTime>ObjMTime ->
%%		    epp:close(Epp),
%%		    true;
%%		_ ->
%%		    check_includes2(Epp, File, ObjMTime)
%%	    end;
%%	{ok, _} ->
%%	    check_includes2(Epp, File, ObjMTime);
%%	{eof, _} ->
%%	    epp:close(Epp),
%%	    false;
%%	{error, _Error} ->
%%	    check_includes2(Epp, File, ObjMTime)
%%    end.
