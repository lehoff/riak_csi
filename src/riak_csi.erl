-module(riak_csi).

%% > erl_csi:start().
%% > RootDir = "/Users/th/gitrepos/basho/riak_ee/rel/riak/lib".
%% > erl_csi:add_all_apps_in_dir(RootDir).
%% > erl_csi:set_ignored_apps(riak_csi:ignore_apps()).

-compile(export_all).

-define(KV_DIR, "/Users/th/gitrepos/basho/riak_kv").

-define(ROOT_DIR, "/Users/th/gitrepos/basho/riak_ee/deps").

root_dir() ->
    "/Users/th/gitrepos/basho/riak_ee/deps".

ignore_apps() ->
    [stdlib, kernel, observer, erts, et, wx, gs, ssl, os_mon,
     snmp, inets, public_key, meck, compiler,
     eper, eunit_formatters, eunit, rebar_lock_deps_plugin,
     ibrowse, sasl, tools, webtool, asn1, neotoma,
     syntax_tools, crypto].

top_level_apps() ->
    [riak_snmp, riak_repl, riak_jmx, riak_search, riak_control].

apps_to_analyse() ->
    [riak_kv, riak_core, riak_repl, riak_pipe, riak_api,
     riak_pb, clique, eleveldb, riak_ensemble, sidejob,
     lager, riaknostic, riak_repl_pb_api, merge_index,
     riak_dt, yokozuna, cluster_info].


load_app_src(App) ->
    FileName = io_lib:format("~s/~p/src/~p.app.src", [root_dir(), App, App]),
    {ok, Terms} = file:consult(FileName),
    Terms.


load_rebar_config(App) ->
    FileName = io_lib:format("~s/~p/rebar.config", [root_dir(), App]),
    {ok, Terms} = file:consult(FileName),
    Terms.


app_src_apps(App) ->
    Apps = [ Config || {application, A, Config} <- load_app_src(App),
                       A == App],
    proplists:get_value(applications, lists:flatten(Apps)) -- ignore_apps().


deps_apps(App) ->
    Config = load_rebar_config(App),
    Deps = proplists:get_value(deps, Config, []),
    [A || {A,_,_} <- Deps] -- ignore_apps().

start_ee() ->
%    erl_csi:start("/Users/th/learning/kv/kv-csi.cfg").
%    erl_csi:start_clean(),
%    add_release("/Users/th/gitrepos/basho/riak_ee/dev/csi"),
%    remove_application(ignore_apps()).
    MFAs = [{erl_csi, add_release, ["/Users/th/gitrepos/basho/riak_ee/dev/csi"]}],
    erl_csi:start(MFAs),
    erl_csi:set_ignored_apps(ignore_apps()).
%    erl_csi:start_clean(),
%    lists:foreach(fun ({M,F,A}) -> erlang:apply(M, F, A) end, MFAs).


%% Too specific to use erl_csi:start/1
start_core() ->
    erl_csi_server:start_clean(),
    xref:add_release(csi, "/Users/th/gitrepos/basho/riak_core/_build/default").

analyse(App) ->
    AppSrcApps = app_src_apps(App),
    DepsApps   = deps_apps(App),
    CalledApps = erl_csi:apps_called_by_app(App),
    RelevantApps = erl_csi:app_transitive_calls(App),
    Apps = %erl_csi:apps() -- [App],
        RelevantApps,
    categorise_apps(Apps, CalledApps, AppSrcApps, DepsApps).

create_dot(App) ->
    Out = io_lib:format("/Users/th/learning/riak_csi/~p-csi.dot", [App]),
    AppsAnalysed = analyse(App),
    ColouredApps = [ {A, category_colour(C)}
                     || {A,C} <- AppsAnalysed],
%    Nodes = [{App, blue}|ColouredApps],
    Nodes = ColouredApps,
    NodesStrings = [ top_node(App) | [ node(N, Colour) || {N, Colour} <- Nodes] ],
    Apps = %erl_csi:apps(),
        erl_csi:app_transitive_calls(App) ++ [App],
    Calls = erl_csi:app2app_calls(Apps),
    CallEdgesStrings = [ call_edges(From, ToList) || {From, ToList} <- Calls ],
    Header = io_lib:format("digraph ~p {", [App]),
    End    = "}",
    file:write_file(Out,
                    lists:flatten([Header, NodesStrings, CallEdgesStrings, End])).

summarise_app(App) ->
    AppsAnalysed = analyse(App),
    [ {C, sum_category(C, AppsAnalysed)}
      || C <- categories() ].

sum_category(C, Apps) ->
    [ A ||
        {A, Cat} <- Apps,
        Cat == C].

print_app_problems(App) ->
    Summary = summarise_app(App),
    Problems = [ CatApps
                 || {C, Apps} = CatApps <- Summary,
                    Apps /= [],
                    not lists:member(C, ['NOT_called_NOT_deps_NOT_appsrc',
                                         'IN_called_IN_deps_IN_appsrc'])],
    io:format("~p problems:~n", [App]),
    [ io:format("~p: ~p~n", [Category, Apps])
      || {Category, Apps} <- Problems].

top_node(Name) ->
    io_lib:format("~p [shape=Mdiamond, color=blue];", [Name]).

node(Name, Colour) ->
    io_lib:format("~p [fillcolor=~p, style=filled];~n", [Name, Colour]).

call_edges(From, ToList) ->
    ToString = string:join( [erlang:atom_to_list(To) || To <- ToList], ","),
    io_lib:format("~p -> { ~s };~n", [From, ToString] ).

colour_apps(Apps, Called, AppSrc, Deps) ->
    Orange = erl_csi:intersection(Called, Deps) -- AppSrc,
    Green  = erl_csi:intersection(Called, erl_csi:intersection(AppSrc,Deps)),
    Yellow = erl_csi:intersection(Called, AppSrc) -- Deps,
    NotCalled = erl_csi:complement(Apps, Called),
    Pink   = erl_csi:intersection(NotCalled, AppSrc) -- Deps,
    HotPink    = erl_csi:intersection(NotCalled, erl_csi:intersection(AppSrc,Deps)),
    Crimson= erl_csi:intersection(NotCalled, Deps) -- AppSrc,
    White  = NotCalled -- erl_csi:union(AppSrc, Deps),
    Red    = Called -- erl_csi:union(AppSrc, Deps),
    lists:flatten([ [ {A, orange} || A <- Orange ],
                    [ {A, green}  || A <- Green],
                    [ {A, yellow} || A <- Yellow],
                    [ {A, pink}   || A <- Pink],
                    [ {A, hotpink}|| A <- HotPink],
                    [ {A, crimson}|| A <- Crimson],
                    [ {A, white}  || A <- White],
                    [ {A, red}    || A <- Red]
                  ]).

categorise_apps(Apps, Called, AppSrc, Deps) ->
    IN_called_IN_deps_NOT_appsrc  = erl_csi:intersection(Called, Deps) -- AppSrc,
    IN_called_IN_deps_IN_appsrc   = erl_csi:intersection(Called, erl_csi:intersection(AppSrc,Deps)),
    IN_called_NOT_deps_IN_appsrc  = erl_csi:intersection(Called, AppSrc) -- Deps,
    NotCalled = erl_csi:complement(Apps, Called),
    NOT_called_NOT_deps_IN_appsrc = erl_csi:intersection(NotCalled, AppSrc) -- Deps,
    NOT_called_IN_deps_IN_appsrc  = erl_csi:intersection(NotCalled, erl_csi:intersection(AppSrc,Deps)),
    NOT_called_IN_deps_NOT_appsrc= erl_csi:intersection(NotCalled, Deps) -- AppSrc,
    NOT_called_NOT_deps_NOT_appsrc = NotCalled -- erl_csi:union(AppSrc, Deps),
    IN_called_NOT_deps_NOT_appsrc = Called -- erl_csi:union(AppSrc, Deps),
    lists:flatten([ [ {A, 'IN_called_IN_deps_NOT_appsrc'} || A <- IN_called_IN_deps_NOT_appsrc ],
                    [ {A, 'IN_called_IN_deps_IN_appsrc'}  || A <- IN_called_IN_deps_IN_appsrc],
                    [ {A, 'IN_called_NOT_deps_IN_appsrc'} || A <- IN_called_NOT_deps_IN_appsrc],
                    [ {A, 'NOT_called_NOT_deps_IN_appsrc'}   || A <- NOT_called_NOT_deps_IN_appsrc],
                    [ {A, 'NOT_called_IN_deps_IN_appsrc'}|| A <-  NOT_called_IN_deps_IN_appsrc],
                    [ {A, 'NOT_called_IN_deps_NOT_appsrc'}|| A <- NOT_called_IN_deps_NOT_appsrc],
                    [ {A, 'NOT_called_NOT_deps_NOT_appsrc'}  || A <- NOT_called_NOT_deps_NOT_appsrc],
                    [ {A, 'IN_called_NOT_deps_NOT_appsrc'}    || A <- IN_called_NOT_deps_NOT_appsrc]
                  ]).

category_colour('IN_called_IN_deps_NOT_appsrc')   -> orange;
category_colour('IN_called_IN_deps_IN_appsrc')    -> green;
category_colour('IN_called_NOT_deps_IN_appsrc')   -> yellow;
category_colour('NOT_called_NOT_deps_IN_appsrc')  -> pink;
category_colour('NOT_called_IN_deps_IN_appsrc')   -> hotpink;
category_colour('NOT_called_IN_deps_NOT_appsrc')  -> crimson;
category_colour('NOT_called_NOT_deps_NOT_appsrc') -> white;
category_colour('IN_called_NOT_deps_NOT_appsrc')  -> red.

categories() ->
    ['IN_called_IN_deps_NOT_appsrc',
     'IN_called_IN_deps_IN_appsrc',
     'IN_called_NOT_deps_IN_appsrc',
     'NOT_called_NOT_deps_IN_appsrc',
     'NOT_called_IN_deps_IN_appsrc',
     'NOT_called_IN_deps_NOT_appsrc',
     'NOT_called_NOT_deps_NOT_appsrc',
     'IN_called_NOT_deps_NOT_appsrc'].
