package = sysinstall
distfiles = sysinstall.sh Makefile DEPENDS README

prefix = /usr/local
exec_prefix = $(prefix)
bindir = $(exec_prefix)/bin


.PHONY: all check dist clean distclean install uninstall

all:

check:

dist:
	rm -R -f $(package) $(package).tar $(package).tar.gz
	mkdir $(package)
	cp -f $(distfiles) $(package)
	tar -c -f $(package).tar $(package)
	gzip $(package).tar
	rm -R -f $(package) $(package).tar

clean:
	rm -R -f $(package) $(package).tar $(package).tar.gz

distclean: clean

install: all
	mkdir -p $(DESTDIR)$(bindir)
	cp -f sysinstall.sh $(DESTDIR)$(bindir)/sysinstall
	chmod +x $(DESTDIR)$(bindir)/sysinstall

uninstall:
	rm -f $(DESTDIR)$(bindir)/sysinstall
