%% 运行方式:
%% 1.打开Terminal窗口,运行shout:start()
%% 2.在另外一个窗口中使用一个可播放在线流媒体的播放器,比如xmms, 播放地址为http://localhost:3000/stream

-module(shout_server).

-export([start/0]).
-import(lists, [map/2, reverse/1]).
-import(tag_len,[file/1]).

-define(CHUNKSIZE, 24576).

start() ->
    spawn(fun() -> 
        start_parallel_server(3000),
        %% 开始休眠
        sleep(infinity)
    end).

start_parallel_server(Port) ->
    {ok, Listen} = gen_tcp:listen(Port, [binary, {packet, 0},{reuseaddr, true},{active, true}]),
    PidSongServer = spawn(fun() -> songs() end),
    spawn(fun() -> par_connect(Listen, PidSongServer) end).

sleep(T) ->
    receive
    after T ->
       true
    end.

par_connect(Listen, PidSongServer) ->
    {ok, Socket} = gen_tcp:accept(Listen),
    spawn(fun() -> par_connect(Listen, PidSongServer) end),
    inet:setopts(Socket, [{packet,0},binary, {nodelay,true},{active, true}]),
    get_request(Socket, PidSongServer, []).

get_request(Socket, PidSongServer, L) ->
    receive
        {tcp, Socket, Bin} ->
            L1 = L ++ binary_to_list(Bin),
            %% split是为了检测头部是否已经完成
            case split(L1, []) of
                %% 头部没有完成，需要更多数据
                more -> get_request(Socket, PidSongServer, L1);
                %% 头部已经完成
                {Request, _Rest} -> got_request_from_client(Request, Socket, PidSongServer)
            end;
        {tcp_closed, Socket} -> void;

        _Any  ->
            %% 其他情况，忽略跳过
            get_request(Socket, PidSongServer, L)
    end.

split("\r\n\r\n" ++ T, L) -> {reverse(L), T};
split([H|T], L)           -> split(T, [H|L]);
split([], _)              -> more.

got_request_from_client(Request, Socket, PidSongServer) ->
    Cmds = string:tokens(Request, "\r\n"),
    Cmds1 = map(fun(I) -> string:tokens(I, " ") end, Cmds),
    is_request_for_stream(Cmds1),
    gen_tcp:send(Socket, [response()]),
    play_songs(Socket, PidSongServer, <<>>).


play_songs(Socket, PidSongServer, SoFar) ->
    Song = rpc(PidSongServer, random_song),
    {File,PrintStr,Header} = unpack_song_descriptor(Song),
    case tag_len:file(File) of
        error ->
            play_songs(Socket, PidSongServer, SoFar);
        {Start, Stop} ->
            io:format("Playing:~p~n",[PrintStr]),
            {ok, S} = file:open(File, [read,binary,raw]), 
            SoFar1 = send_file(S, {0,Header}, Start, Stop, Socket, SoFar),
            file:close(S),
            play_songs(Socket, PidSongServer, SoFar1)
    end.


send_file(S, Header, OffSet, Stop, Socket, SoFar) ->
    %% OffSet - 待播放的第一个字节
    %% Stop   - 可以播放的最后一个字节
    Need = ?CHUNKSIZE - size(SoFar),
    Last = OffSet + Need,
    if
        Last >= Stop ->
            %% 没有足够的数据，尽可能多的读取然后返回
            Max = Stop - OffSet,
            {ok, Bin} = file:pread(S, OffSet, Max),
            list_to_binary([SoFar, Bin]);
        true ->
            {ok, Bin} = file:pread(S, OffSet, Need),
            write_data(Socket, SoFar, Bin, Header),
            send_file(S, bump(Header),
                OffSet + Need,  Stop, Socket, <<>>)
    end.


write_data(Socket, B0, B1, Header) ->
    %% 检测得到的数据量是否正确。
    case size(B0) + size(B1) of
        ?CHUNKSIZE ->
            case gen_tcp:send(Socket, [B0, B1, the_header(Header)]) of
                ok -> true;
                {error, closed} ->
                    %% 播放器终止连接后，关闭服务
                    exit(playerClosed)
            end;
        _Other ->
            io:format("Block length Error: B0 = ~p b1=~p~n",
                [size(B0), size(B1)])
    end.

bump({K, H})     -> {K+1, H}.

the_header({K, H}) ->
    case K rem 5 of
        0 -> H;
        _ -> <<0>>
    end.


is_request_for_stream(_) -> true.


response() ->
    ["ICY 200 OK\r\n",
        "icy-notice1: <BR>This stream requires",
        "<a href=\"http://www.winamp.com/\">Winamp</a><BR>\r\n",
        "icy-notice2: Erlang Shoutcast server<BR>\r\n",
        "icy-name: Erlang mix\r\n",
        "icy-genre: Pop Top 40 Dance Rock\r\n",
        "icy-url: http://localhost:3000\r\n",
        "content-type: audio/mpeg\r\n",
        "icy-pub: 1\r\n",
        "icy-metaint: ",integer_to_list(?CHUNKSIZE),"\r\n",
        "icy-br: 96\r\n\r\n"]. 


songs() ->
    {ok,[SongList]} = file:consult("mp3data.tmp"),
    random_seed(),
    songs_loop(SongList).

random_seed() ->
    {_,_,X} = erlang:now(),
    {H,M,S} = time(),
    H1 = H * X rem 32767,
    M1 = M * X rem 32767,
    S1 = S * X rem 32767,
    put(random_seed, {H1,M1,S1}).

songs_loop(SongList) ->
    receive
        {From, random_song} ->
            I = random:uniform(length(SongList)),
            Song = lists:nth(I, SongList),
            From ! {self(), Song},
            songs_loop(SongList)
    end.

rpc(Pid, Q) ->
    Pid ! {self(), Q},
    receive
        {Pid, Reply} ->
            Reply
    end.

unpack_song_descriptor({File, {_Tag,Info}}) ->
    PrintStr = list_to_binary(make_header1(Info)),
    L1 = ["StreamTitle='",PrintStr,
        "';StreamUrl='http://localhost:3000';"],
    %% io:format("L1=~p~n",[L1]),
    Bin = list_to_binary(L1),
    Nblocks = ((size(Bin) - 1) div 16) + 1,
    NPad = Nblocks*16 - size(Bin), 
    Extra = lists:duplicate(NPad, 0),
    Header = list_to_binary([Nblocks, Bin, Extra]),
    %% Header - 本服务器的Header
    {File, PrintStr, Header}.

make_header1([{track,_}|T]) -> make_header1(T);    
make_header1([{Tag,X}|T]) -> [atom_to_list(Tag),": ",X," "|make_header1(T)];
make_header1([]) -> [].
