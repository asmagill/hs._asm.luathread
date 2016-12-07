PREFIX ?= ~/.hammerspoon
HS_APPLICATION ?= /Applications
VERSION ?= 0.0

all:

install:
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C ../.. $@
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C .. $@
	-for f in [a-z_]* ; do [ -d $$f ] && echo "-- $$f --" && HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C $$f $@ ; done
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C drawing/color $@

uninstall:
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C ../.. $@
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C .. $@
	-for f in [a-z_]* ; do [ -d $$f ] && echo "-- $$f --" && HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C $$f $@ ; done
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C drawing/color $@

clean:
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C ../.. $@
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C .. $@
	-for f in [a-z_]* ; do [ -d $$f ] && echo "-- $$f --" && HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C $$f $@ ; done
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=$(PREFIX) $(MAKE) -C drawing/color $@

release:
	rm -fr ../../luathread
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=luathread $(MAKE) -C ../.. clean install
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=../luathread $(MAKE) -C .. clean install
	-for f in [a-z_]* ; do [ -d $$f ] && echo "-- $$f --" && HS_APPLICATION=$(HS_APPLICATION) PREFIX=../../../luathread $(MAKE) -C $$f clean install ; done
	HS_APPLICATION=$(HS_APPLICATION) PREFIX=../../../../luathread $(MAKE) -C drawing/color clean install
	pushd ../../luathread ; tar -cf ../luathread-v$(VERSION).tar hs ; gzip -9 ../luathread-v$(VERSION).tar ; popd

.phony: all install uninstall release clean
