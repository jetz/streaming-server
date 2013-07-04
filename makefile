.SUFFIXES: .erl .beam

OUT=./beam

.erl.beam:
	erlc -W $< ; mv $@ ${OUT}

ERL=erl -boot start_clean

MODS=shout_server mp3_parser mp3_sync tag_len lib_find

all: compile

compile: ${MODS:%=%.beam}

run: 
	${ERL} -s application start ARG1 ARG2
clean:
	rm -rf *.beam erl_crash.dump
