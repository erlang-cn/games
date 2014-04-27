-module(game_log).
-author("Dayneko Roman <me@h0.org.ua>").
-copyright("Kakaranet").
-behaviour(gen_server).
-include_lib("kvs/include/kvs.hrl").
-include_lib("db/include/game_log.hrl").
-include_lib("server/include/requests.hrl").
-compile(export_all).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-define(SERVER, ?MODULE).
-record(state, {history = []}).

start_link() -> gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).
mypid() -> gen_server:call(?SERVER, mypid).
clear_history() -> gen_server:cast(?SERVER, clear_history).
get_history() -> gen_server:call(?SERVER, get_history).
put(PI,Event,State) -> gen_server:cast(?SERVER, {log_event, PI, Event, State}).
timestamp() -> {MegaSec, Sec, MiliSec} = erlang:now(), MegaSec * 1000 * 1000 * 1000  + Sec * 1000 + MiliSec.

init([]) -> {ok, #state{}}.
handle_call(mypid, _From, State) -> {reply, {ok, self()}, State};
handle_call(get_history, _From, #state{history = History} = State) -> {reply, {ok, lists:reverse(History)}, State};
handle_call(_Request, _From, State) -> 
    gas:info(?MODULE, "Event Log: call message ~p from ~p", [_Request, _From]),
    Reply = ok,
    {reply, Reply, State}.
handle_cast({log_event, PI, #game_event{game = GameId, event = EventName, args = Args} = Event, GameState}, #state{history = History} = State) ->

    EventLogEntry = 
        #event_log{
           feed_id = {GameId, PI#'PlayerInfo'.id},
           id = {timestamp(), GameId, PI#'PlayerInfo'.id},
           game_id = GameId,
           event = EventName,
           timestamp = calendar:now_to_universal_time(erlang:now()),
           game_event = Event},

    gas:info(?MODULE, "Event Log: ~p", [EventLogEntry]),
    kvs:add(EventLogEntry),

    {ok,GL} = kvs:get(game_log,{GameId, PI#'PlayerInfo'.id}),
    ProtocolStats = GL#game_log.protocol_stat,
    PS = case is_list(ProtocolStats) of true -> ProtocolStats; _ -> [] end,
    Stats = case lists:keyfind(EventName,1,PS) of
        {EventName,Count} -> lists:keyreplace(EventName,1,PS,{EventName,Count+1});
        false -> [{EventName,1}|PS] end,
    kvs:put(GL#game_log{protocol_stat=Stats}),

    {noreply, State#state{history = [Event | History]}};
handle_cast(clear_history, State) -> {noreply, State#state{history = []}};
handle_cast(_Msg, State) -> gas:info(?MODULE, "Event Log: cast message ~p", [_Msg]), {noreply, State}.
handle_info(_Info, State) -> gas:info(?MODULE, "Event Log: info message ~p", [_Info]), {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.