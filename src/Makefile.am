# Makefile.am for mail-server/src

yncludedir = @yncludedir@/mail-server
schemadir  = /etc/openldap/schema

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

schema_DATA = SUSE-Mail.schema

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(module_DATA) $(desktop_DATA) $(schema_DATA)

include $(top_srcdir)/Makefile.am.common
