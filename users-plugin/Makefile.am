# Makefile.am for mail-server/src

yncludedir = @yncludedir@/mail-server

client_DATA =			\
	users_plugin_mail.ycp   \
	users_plugin_mail_groups.ycp

module_DATA =			\
	UsersPluginMail.pm      \
	UsersPluginMailGroups.pm

EXTRA_DIST = $(client_DATA) $(module_DATA)

include $(top_srcdir)/Makefile.am.common
