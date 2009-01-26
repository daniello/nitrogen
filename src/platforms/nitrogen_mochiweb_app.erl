% Nitrogen Web Framework for Erlang
% Copyright (c) 2008-2009 Rusty Klophaus
% See MIT-LICENSE for licensing information.

-module (nitrogen_mochiweb_app).
-export([start/0, stop/0]).
-export([loop/2]).

-include_lib("kernel/include/file.hrl").

start() ->
	% Initialize Nitrogen.
	wf:init(),

	% Start the Mochiweb server.
	Port = nitrogen:get_port(),
	DocumentRoot = nitrogen:get_wwwroot(),
	Options = [{ip, "0.0.0.0"}, {port, Port}],
	Loop = fun (Req) -> ?MODULE:loop(Req, DocumentRoot) end,
	mochiweb_http:start([{name, get_name()}, {loop, Loop} | Options]).
	
loop(Req, DocRoot) ->
	"/" ++ Path = Req:get(path),
	case Req:get(method) of
		Method when Method =:= 'GET'; Method =:= 'HEAD' ->
			case check_if_file_exists(Path, DocRoot) of
			  true ->
			    serve_file(Req, Path, DocRoot);
			  _    ->
			    case Path of
			      "" -> wf_mochiweb:loop(Req, web_index);
			      _  -> wf_mochiweb:loop(Req)
			    end
			end;
			
		'POST' ->
			case Path of
				"" -> wf_mochiweb:loop(Req, web_index);
				_ -> wf_mochiweb:loop(Req)
			end;
		_ ->
		Req:respond({501, [], []})
	end.

not_found(Req) -> wf_mochiweb:loop(Req, '404').

check_if_file_exists(Path, DocRoot) ->
  case mochiweb_util:safe_relative_path(Path) of
        undefined ->
            false;
        RelPath ->
            FullPath = filename:join([DocRoot, RelPath]),
            File = case filelib:is_dir(FullPath) of
                       true ->
                           filename:join([FullPath, "index.html"]);
                       false ->
                           FullPath
                   end,
            case file:read_file_info(File) of
                {ok, _} ->
                    true;
                {error, _} ->
                    false
            end
    end.

%% modified version of serve_file/3 from mochiweb_request.erl (Mochiweb)
%% the intention is to uese notrogen's 404 instad of 
%% @spec serve_file(Path, DocRoot, ExtraHeaders) -> Response
%% @doc Serve a file relative to DocRoot.
serve_file(Req, Path, DocRoot) ->
    case mochiweb_util:safe_relative_path(Path) of
        undefined ->
            not_found(Req);
        RelPath ->
            FullPath = filename:join([DocRoot, RelPath]),
            File = case filelib:is_dir(FullPath) of
                       true ->
                           filename:join([FullPath, "index.html"]);
                       false ->
                           FullPath
                   end,
            case file:read_file_info(File) of
                {ok, FileInfo} ->
                    LastModified = httpd_util:rfc1123_date(FileInfo#file_info.mtime),
                    case Req:get_header_value("if-modified-since") of
                        LastModified ->
                            Req:respond({304, [], ""});
                        _ ->
                            case file:open(File, [raw, binary]) of
                                {ok, IoDevice} ->
                                    ContentType = mochiweb_util:guess_mime(File),
                                    Res = Req:ok({ContentType,
                                              [{"last-modified", LastModified}],
                                              {file, IoDevice}}),
                                    file:close(IoDevice),
                                    Res;
                                _ ->
                                    not_found(Req)
                            end
                    end;
                {error, _} ->
                    not_found(Req)
            end
    end.
	
stop() -> 
	% Stop the mochiweb server.
	mochiweb_http:stop(get_name()),
	ok.
	
get_name() ->
	case application:get_application() of
		{ok, App} -> App;
		undefined -> nitrogen
	end.