PROJECT = riak_csi
PROJECT_VERSION = 0.1

DEPS = erl_csi

dep_erl_csi = cp ${HOME}/gitrepos/lehoff/erl_csi

include erlang.mk
