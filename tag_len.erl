-module(tag_len).

-export([test/0,file/1]).

-import(lists, [foreach/2, map/2]).
-import(lib_find, [files/3, files/5]).

test() ->
    Files = lib_find:files("/home/jetz/music_test", "/*.mp3", true),
    map(fun(F) -> file(F) end, Files).

file(File) ->
    read_id3_tag(File).

read_id3_tag(File) ->
    case file:open(File, [read,binary,raw]) of
        {ok, S} ->
	    Size = filelib:file_size(File),
            Result = analyse(S, Size),
	    file:close(S),
	    Result;
        _Error ->
            error
    end.

analyse(S, Size) ->
    case (catch analyse1(S, Size)) of
	{'EXIT', _Why} ->
	    io:format("_Why=~p~n",[_Why]),
	    error;
	StartStop ->
	    StartStop
    end.

analyse1(S, Size) ->
    {ok, Bin}  = file:pread(S, 0, 10000),
    {ok, StartTrust} = mp3_sync:find_sync(Bin, 1),
    {Type, StartUntrust} = parse_start_tag(Bin),
    Stop = parse_end_tag(S, Size),
    if 
	StartTrust == StartUntrust ->
	    true;
	true ->
	    io:format("** error in header code:  real=~p Type=~p Val=~p~n",
		      [StartTrust, Type, StartUntrust])
    end,
    {StartTrust, Stop}.


parse_start_tag(<<$I,$D,$3,3,0,_Unsync:1,_Extended:1,_Experimental:1,
		 _:5,K:32,_/binary>>) ->
    Tag = "ID3v2.3.0",
    Size = syncsafe2int(K),
    {Tag, Size+10};
parse_start_tag(<<$I,$D,$3,4,0,_Unsync:1,_Extended:1,_Experimental:1,
		 Footer:1,_:4,K:32,_/binary>>) ->
    Tag = "ID3v2.3.0",
    Size = syncsafe2int(K),
    Size1 = case Footer of 
		1 -> 10 + Size;
		0 -> Size
	    end,
    {Tag, Size1+1};
parse_start_tag(<<X:10/binary,_/binary>>) ->
    io:format("strange start tag~p~n",[X]),
    {error, 1}.

parse_end_tag(S, Size) ->
    {ok, B2} = file:pread(S, Size-128, 128),
    parse_v1_tag(B2, Size).
    
parse_v1_tag(<<$T,$A,$G,_/binary>>, Size) ->
    Size - 128;
parse_v1_tag(_, Size) ->
    Size.

syncsafe2int(N) ->
    <<_:1,N1:7,_:1,N2:7,_:1,N3:7,_:1,N4:7>> = <<N:32>>,
    <<I:32>> = <<0:4,N1:7,N2:7,N3:7,N4:7>>, I.
