PERL?=/usr/bin/perl
PREFIX?=/usr/local/mailnews
OWNER?=news
GROUP?=news

.PHONY: default clean test-perls

default:
	@echo Say make install, or clean

clean:
	rm -rf bin
	rm -f -- *~

test-perls:
	for D in cmd.pl feeder.pl lister.pl sdba.pl newgrp.pl \
		mn_config.pm mn_subs.pm mn_mime.pm mn_intl.pm; \
	do \
		perl -I. -wc -Mstrict "$$D"; \
	done

.PHONY: install-dirs install-perls install-conf install-thunks install

install-dirs:
	mkdir -p "$(PREFIX)"
	install -d -m 0755 -o "$(OWNER)" -g "$(GROUP)" "$(PREFIX)/bin"
	install -d -m 0755 -o "$(OWNER)" -g "$(GROUP)" "$(PREFIX)/etc"
	install -d -m 0755 -o "$(OWNER)" -g "$(GROUP)" "$(PREFIX)/lib"
	install -d -m 0755 -o "$(OWNER)" -g "$(GROUP)" "$(PREFIX)/lib/mailnews"

install-perls:
	install -c -m 0755 -o "$(OWNER)" -g "$(GROUP)" \
		cmd.pl feeder.pl lister.pl sdba.pl newgrp.pl \
		mn_subs.pm mn_mime.pm mn_intl.pm \
		"$(PREFIX)/lib/mailnews/"

install-conf:
	install -c -m 0600 -o "$(OWNER)" -g "$(GROUP)" mn_config.pm "$(PREFIX)/etc/"

install-thunks:
	sh ./make_thunk.sh "$(OWNER)" "$(GROUP)" "$(PERL)" "$(PREFIX)" cmd
	sh ./make_thunk.sh "$(OWNER)" "$(GROUP)" "$(PERL)" "$(PREFIX)" feeder
	sh ./make_thunk.sh "$(OWNER)" "$(GROUP)" "$(PERL)" "$(PREFIX)" lister
	sh ./make_thunk.sh "$(OWNER)" "$(GROUP)" "$(PERL)" "$(PREFIX)" sdba
	sh ./make_thunk.sh "$(OWNER)" "$(GROUP)" "$(PERL)" "$(PREFIX)" newgrp

install: install-dirs install-perls install-conf install-thunks
