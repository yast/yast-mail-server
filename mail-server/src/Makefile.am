# Makefile.am for mail-server/src

SUBDIRS = YaPI

yncludedir = @yncludedir@/mail-server
schemadir  = /etc/openldap/schema
permissionsdir  = /etc/permissions.d

client_DATA =			\
	mail-server.ycp		\
	mail-server_auto.ycp	\
	mail-server_proposal.ycp

ynclude_DATA =			\
	helps.ycp		\
	wizards.ycp		\
	dialogs.ycp		\
	complex.ycp

ycpchook = mail-server
$(ycpchook):
	ln -sf . $@

desktop_DATA =			\
	mail-server.desktop

module_DATA =			\
	MailServer.ycp		

schema_DATA = suse-mailserver.schema

permissions_DATA = mail-server.perm

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(module_DATA) $(desktop_DATA) \
	     $(schema_DATA) $(permissions_DATA)

include $(top_srcdir)/Makefile.am.common
