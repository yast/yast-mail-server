# Makefile.am for mail-server/src

yncludedir = @yncludedir@/mail-server

client_DATA =			\
	mail-server.ycp		\
	mail-server_auto.ycp	\
	mail-server_proposal.ycp

ynclude_DATA =			\
	helps.ycp		\
	wizards.ycp		\
	dialogs.ycp		\
	complex.ycp

desktop_DATA =			\
	mail-server.desktop

module_DATA =			\
	MailServer.ycp		\
	MailServer.pm

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(module_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common
