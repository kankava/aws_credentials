%% @doc This is the behaviour definition for a credential provider
%% module and it iterates over a list of providers. You may set the
%% `credential_providers` Erlang environment variable if you want to
%% restrict checking only a certain subset of the default list.
%%
%% Default order of checking for credentials is:
%% <ol>
%%   <li>Erlang application environment</li>
%%   <li>OS environment</li>
%%   <li>Credentials from AWS file</li>
%%   <li>ECS Task credentials</li>
%%   <li>EC2 credentials</li>
%% </ol>
%%
%% Providers are expected to implement a function called `fetch/1' which
%% takes as its argument a proplist of options which may influence the
%% operation of the provider.  The fetch/1 function should return either
%% `{ok, Credentials, Expiration}' or `{error, Reason}'.
%%
%% If a provider returns {ok, ...} then evaluation stops at that provider.
%% If it returns {error, ...} then the next provider is executed in order
%% until either a set of credentials are returns or the tuple
%% `{error, no_credentials}' is returned.
%%
%% If a new provider is desired, the behaviour interface should be
%% implemented and its module name added to the default list.
%% @end
-module(aws_credentials_provider).

-export([fetch/0, fetch/1]).

-type options() :: #{provider() => map()}.
-type expiration() :: binary() | pos_integer() | infinity.
-type provider() :: aws_credentials_env
                  | aws_credentials_file
                  | aws_credentials_ecs
                  | aws_credentials_ec2.
-export_type([ options/0, expiration/0 ]).

-callback fetch(options()) ->
  {ok, aws_credentials:credentials(), expiration()} | {error, any()}.

-include_lib("kernel/include/logger.hrl").

-define(DEFAULT_PROVIDERS, [aws_credentials_env,
                            aws_credentials_file,
                            aws_credentials_ecs,
                            aws_credentials_ec2]).

-spec fetch() -> {'error', 'no_credentials'} | aws_credentials:credentials().
fetch() ->
    fetch([]).

-spec fetch([]) -> {'error', 'no_credentials'} | aws_credentials:credentials().
fetch(Options) ->
    Providers = get_env(credential_providers, ?DEFAULT_PROVIDERS),
    evaluate_providers(Providers, Options).

-spec evaluate_providers([provider() | {provider(), options()}], []) ->
        {'error', no_credentials} | aws_credentials:credentials().
evaluate_providers([], _Options) -> {error, no_credentials};
evaluate_providers([ Provider | Providers ], Options) ->
    case Provider:fetch(Options) of
        {error, _} = Error ->
            ?LOG_ERROR("Provider ~p reports ~p",
                       [Provider, Error],
                       #{domain => [aws_credentials]}),
            evaluate_providers(Providers, Options);
        Credentials -> Credentials
    end.

-spec get_env(atom(), [provider()]) -> any().
get_env(Key, Default) ->
    case application:get_env(aws_credentials, Key) of
        undefined -> Default;
        {ok, Value} -> Value
    end.
